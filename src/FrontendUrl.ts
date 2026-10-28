import * as Alchemy from "alchemy";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";

// Owned here rather than by the frontend stack so the parser's CORS origin
// and the frontend's Worker name come from one place without a stack cycle.
export const FrontendUrl = Effect.gen(function* () {
  const { stage } = yield* Alchemy.Stack;
  const workersSubdomain = yield* Config.String("WORKERS_SUBDOMAIN");
  const frontendWorkerName = `dekin-frontend-${stage}`;

  return {
    frontendWorkerName,
    frontendOrigin: `https://${frontendWorkerName}.${workersSubdomain}.workers.dev`,
  };
});
