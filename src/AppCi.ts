import * as Alchemy from "alchemy";
import * as Namespace from "alchemy/Namespace";
import * as Cloudflare from "@alchemy.run/cloudflare";
import * as GitHub from "@alchemy.run/github";
import * as Effect from "effect/Effect";

const GITHUB_OWNER = "Dekin-Ydays";
const APP_REPOSITORIES = ["video-parser", "frontend"] as const;

// Repository secrets are not per stage, so only prod writes them.
export const AppCi = Effect.gen(function* () {
  const { stage } = yield* Alchemy.Stack;
  if (stage !== "prod") return;

  const { accountId } = yield* yield* Cloudflare.CloudflareEnvironment;
  const token = yield* Cloudflare.ApiToken.AccountApiToken("AppCiToken", {
    name: "dekin-app-ci",
    policies: [
      {
        effect: "allow",
        permissionGroups: [
          "Workers Scripts Write",
          "Workers Containers Write",
          "Secrets Store Write",
          "Account Settings Read",
          "Workers Tail Read",
        ],
        resources: { [`com.cloudflare.api.account.${accountId}`]: "*" },
      },
    ],
  });

  for (const repository of APP_REPOSITORIES) {
    yield* GitHub.Secrets({
      owner: GITHUB_OWNER,
      repository,
      secrets: {
        CLOUDFLARE_API_TOKEN: token.value,
        CLOUDFLARE_ACCOUNT_ID: accountId,
      },
    }).pipe(Namespace.push(repository));
  }
});
