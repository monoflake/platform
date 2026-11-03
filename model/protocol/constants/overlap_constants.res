/**
 * The overlap's constants that are facts of the design, printed for the runner as one JSON object,
 * RFC w0w82. Top is a bound of the search and stays in overlap.cfg.
 */
let constants = () => dict{"Reach": Window.reach}

Console.log(JSON.stringifyAny(constants())->Option.getOr("{}"))
