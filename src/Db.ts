import * as Alchemy from "alchemy";
import * as Output from "alchemy/Output";
import * as RemovalPolicy from "alchemy/RemovalPolicy";
import * as Neon from "@alchemy.run/neon";
import * as Effect from "effect/Effect";
import * as Redacted from "effect/Redacted";

// Prod owns the Neon project; every other stage gets a schema-only branch
// of it, so destroying a non-prod stage never touches prod data.
export const Db = Effect.gen(function* () {
  const { stage } = yield* Alchemy.Stack;

  const connectionUri =
    stage === "prod"
      ? (yield* Neon.Project("Db", {
          name: "dekin",
          region: "aws-eu-central-1",
          pgVersion: 17,
        }).pipe(RemovalPolicy.retain())).connectionUri
      : (yield* Neon.Branch("Branch", {
          project: yield* Neon.Project.ref("Db", { stage: "prod" }),
          name: stage,
          initSource: "schema-only",
        })).connectionUri;

  return {
    databaseUrl: connectionUri.pipe(Output.map((url) => Redacted.make(url))),
  };
});
