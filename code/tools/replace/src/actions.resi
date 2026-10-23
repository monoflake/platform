/***
 * What is restarted on a test machine while hello is asked, each waited on until it serves, and
 * the shells reading its clock and leaving every unit active, RFC ehm48.
 */

/** One restart, as the report names it, and the shell taking it and waiting until it serves. */
type action = {name: string, shell: string}

/** The driver, the entry and containerd restarted, in that order. */
let restarts: array<action>

/** The units a run touches, the entry's socket among them where the machine has one. */
let units: array<string>

/** The shell starting every one of `units` the machine has, a run's last word however it ends. */
let kept: string

/** The shell printing each of `units` the machine has and its state, one to a line. */
let states: string

/** The shell printing the machine's clock in milliseconds. */
let clock: string

/** Every unit `states` printed active, or those that are not. */
let active: string => result<unit, string>
