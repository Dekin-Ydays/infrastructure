import { createHash } from "node:crypto";
import * as Alchemy from "alchemy";
import * as Output from "alchemy/Output";
import * as RemovalPolicy from "alchemy/RemovalPolicy";
import * as Cloudflare from "@alchemy.run/cloudflare";
import * as Effect from "effect/Effect";
import * as Redacted from "effect/Redacted";

export const Videos = Effect.gen(function* () {
  const { stage } = yield* Alchemy.Stack;
  const isProd = stage === "prod";
  const { accountId } = yield* yield* Cloudflare.CloudflareEnvironment;

  const bucket = yield* Cloudflare.R2.Bucket("Videos", {
    name: `dekin-videos-${stage}`,
    locationHint: "weur",
    forceDestroy: !isProd,
  }).pipe(RemovalPolicy.retain(isProd));

  // R2's S3 API authenticates with an API token: the access key id is the
  // token id and the secret is the SHA-256 hex digest of the token value.
  const s3Token = yield* Cloudflare.ApiToken.AccountApiToken("VideosS3Token", {
    name: `dekin-videos-s3-${stage}`,
    policies: [
      {
        effect: "allow",
        permissionGroups: [
          "Workers R2 Storage Bucket Item Read",
          "Workers R2 Storage Bucket Item Write",
        ],
        resources: bucket.bucketName.pipe(
          Output.map((name) => ({
            [`com.cloudflare.edge.r2.bucket.${accountId}_default_${name}`]: "*",
          })),
        ),
      },
    ],
  });

  return {
    bucketName: bucket.bucketName,
    s3Endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
    s3AccessKeyId: s3Token.tokenId,
    s3SecretAccessKey: s3Token.value.pipe(
      Output.map((value) =>
        Redacted.make(
          createHash("sha256").update(Redacted.value(value)).digest("hex"),
        ),
      ),
    ),
  };
});
