/**
 * What a node's host answers under `/api/`, as the console reads it: the part of infra's
 * apps/deploy/panel/src/lib/api.ts it asks for, and the meter's shapes host passes on.
 */

/** Cores that run at one frequency, which the meter reads once for all of them. */
export interface CoreCluster {
	cores: number[];
	/** MHz at most. */
	max_frequency: number | null;
}

/** What does not change while the machine is up, as the meter reads it. */
export interface MachineInfo {
	model: string | null;
	kernel: string | null;
	cores: number;
	clusters: CoreCluster[];
	/** Bytes. */
	memory: number;
	swap: number;
	/** Bytes, of the filesystem the meter keeps its hours on. */
	storage: number | null;
	/** Seconds since the epoch. */
	booted: number | null;
}

/** One second of the machine: a value per metric. */
export interface Sample {
	at: number;
	values: Record<string, number>;
}

/** `/api/node/now`. */
export interface Now {
	info: MachineInfo;
	sample: Sample;
}

export interface Summary {
	average: number;
	minimum: number;
	maximum: number;
	count: number;
}

/** A bucket of time, named by when it starts, each metric summarized over it. */
export interface Point {
	at: number;
	values: Record<string, Summary>;
}

export type Grain = 'second' | 'minute' | 'hour';
