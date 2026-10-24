/***
 * A send's request posted on the machine a deployment runs on, over ssh, as an address on its
 * bridge is reached from there alone, RFC p8e8k.
 */

/**
 * The shell posting what stdin holds to a URL and printing the body answered and then its status
 * on a line of its own, or why the URL is not one to put in a shell.
 */
let posted: string => result<string, string>

/** What `posted` printed, the status and the body, or why it is none. */
let readPosted: Uint8Array.t => result<(int, Uint8Array.t), string>

/** The host component's `post` through ssh's arguments, its options and then the machine. */
let post: array<string> => Host.Handed.post
