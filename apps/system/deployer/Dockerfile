# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
# The deployer: its own code bundled into one file, beside a node_modules holding wrangler alone,
# the one production dependency, as pnpm's lockfile pins it. Built from the repository root by
# `mise run image`, which reads NODE_VERSION from the workspace's mise.toml. See
# spec/architecture/deployer.md.
ARG NODE_VERSION

FROM node:${NODE_VERSION}-slim AS build
WORKDIR /src
# The pnpm the repository names, since this Node carries no corepack to pick it.
COPY package.json ./
RUN npm install --global "$(node -p "require('./package.json').packageManager")"
COPY . .
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
	pnpm install --frozen-lockfile --filter "@monoflake/deployer..." \
	&& pnpm --filter @monoflake/deployer run bundle \
	&& pnpm --filter @monoflake/deployer deploy --prod /deployer

FROM node:${NODE_VERSION}-slim
# What wrangler's own requests trust; the artifacts are opened by the deployer itself.
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends ca-certificates \
	&& rm -rf /var/lib/apt/lists/*
WORKDIR /deployer
COPY --from=build /deployer/node_modules ./node_modules
COPY --from=build /src/apps/system/deployer/dist/main.mjs ./
# The image's own `node` user, by number, so host runs it as that and nothing more.
USER 1000:1000
ENV NODE_ENV=production
CMD ["node", "main.mjs"]
