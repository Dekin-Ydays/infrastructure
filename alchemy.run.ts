import * as Alchemy from "alchemy";
import * as Cloudflare from "@alchemy.run/cloudflare";
import * as GitHub from "@alchemy.run/github";
import * as Neon from "@alchemy.run/neon";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { AppCi } from "./src/AppCi.ts";
import { Db } from "./src/Db.ts";
import { FrontendUrl } from "./src/FrontendUrl.ts";
import { Videos } from "./src/Videos.ts";

export default Alchemy.Stack(
  "dekin-infrastructure",
  {
    providers: Layer.mergeAll(
      Cloudflare.providers(),
      Neon.providers(),
      GitHub.providers(),
    ),
    state: Cloudflare.state(),
  },
  Effect.gen(function* () {
    const videos = yield* Videos;
    const db = yield* Db;
    const frontendUrl = yield* FrontendUrl;
    yield* AppCi;

    return { ...videos, ...db, ...frontendUrl };
  }),
);
