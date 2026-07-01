from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text()


class RepositoryContractsTest(unittest.TestCase):
    def test_ec2_worker_options_precede_start_subcommand(self) -> None:
        script = read("ec2/bin/cursor-worker-start")
        command_start = script.index('cmd=(')
        command_end = script.index('exec "${cmd[@]}"')
        command = script[command_start:command_end]
        self.assertIn('"$AGENT_BIN" worker', command)
        self.assertNotIn('"$AGENT_BIN" worker start', command)
        self.assertIn("cmd+=(start)", command)
        self.assertLess(command.index("--pool"), command.index("cmd+=(start)"))

    def test_scaling_uses_documented_worker_endpoints(self) -> None:
        autoscaler = read("ec2/bin/cursor-workers-autoscale")
        metrics = read("ec2/bin/cursor-workers-publish-metrics")
        for source in (autoscaler, metrics):
            self.assertNotIn('body.get("claimed")', source)
            self.assertNotIn(".claimed == true", source)
            self.assertNotIn(".connected == true", source)
        self.assertIn("%{http_code}", autoscaler)
        self.assertIn("cursor_self_hosted_worker_session_active", metrics)

    def test_production_defaults_are_not_stale(self) -> None:
        repository_text = "\n".join(
            path.read_text()
            for path in ROOT.rglob("*")
            if path.is_file()
            and ".git" not in path.parts
            and ".terraform" not in path.parts
            and "tests" not in path.parts
        )
        self.assertNotIn("channel=lab", repository_text)
        self.assertNotIn('worker_image_tag    = "latest"', repository_text)
        self.assertNotIn('default     = "1.30"', repository_text)
        self.assertNotIn("NODE_VERSION=25", repository_text)

    def test_makefile_does_not_put_secret_values_in_arguments(self) -> None:
        makefile = read("Makefile")
        self.assertNotIn("--from-literal", makefile)
        self.assertNotIn('--secret-string "$', makefile)
        self.assertNotIn("\nexport\n", makefile)
        self.assertIn("scripts/put-secret-value.sh", makefile)
        self.assertIn("scripts/create-k8s-secret.sh", makefile)

    def test_kubernetes_worker_has_restricted_baseline(self) -> None:
        manifest = read("kube/manifests/workers.tpl.yaml")
        for expected in (
            "runAsNonRoot: true",
            "allowPrivilegeEscalation: false",
            "seccompProfile:",
            "automountServiceAccountToken: false",
            "ephemeral-storage:",
            "emptyDir:",
            "SCM_TOKEN_FILE",
        ):
            self.assertIn(expected, manifest)

    def test_local_markdown_links_resolve(self) -> None:
        failures: list[str] = []
        for path in ROOT.rglob("*.md"):
            if ".terraform" in path.parts:
                continue
            for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", path.read_text()):
                target = target.split("#", 1)[0]
                if not target or "://" in target or target.startswith("mailto:"):
                    continue
                if not (path.parent / target).resolve().exists():
                    failures.append(f"{path.relative_to(ROOT)}: {target}")
        self.assertEqual([], failures)


if __name__ == "__main__":
    unittest.main()
