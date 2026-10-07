/**
 * The deployer as host runs it: its configuration from the environment, its records in `/data`, and
 * one HTTP server. It starts with nothing configured and refuses every run until it is. See
 * spec/architecture/deployer.md.
 */
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { serve } from '@hono/node-server';
import { configOf, tokenFor } from './config.ts';
import { Deployer } from './deploy.ts';
import { GitHub } from './github.ts';
import { handle } from './server.ts';
import { Store } from './store.ts';
import { run } from './wrangler.ts';

const config = configOf(process.env);
mkdirSync(config.data, { recursive: true });
const store = new Store(join(config.data, 'deployer.db'));
const github = new GitHub((repository) => tokenFor(repository, process.env));
const deployer = new Deployer({ config, store, github, wrangler: run });

if (config.sources.length === 0) console.log('deployer: DEPLOY_SOURCES names no repository');
if (config.owners.size === 0) console.log('deployer: WORKER_OWNERS names no Worker');

serve({
	port: config.port,
	hostname: '::',
	fetch: (request) =>
		handle(request, {
			token: config.token,
			readToken: config.readToken,
			owned: (worker) => config.owners.has(worker),
			notice: (notice) => deployer.notice(notice),
			rollback: (rollback) => deployer.rollback(rollback),
			deploys: (limit, before) => store.list(limit, before),
		}),
});
console.log(`deployer: listening on ${config.port}${config.dry ? ', every deploy dry' : ''}`);
