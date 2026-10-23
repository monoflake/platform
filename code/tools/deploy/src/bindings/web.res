/*** What the tool takes of the web's Fetch API, to call a control and ask its gateway. */
type response
type init = {method: string, headers: dict<string>, body?: string}

@val external fetch: (string, init) => promise<response> = "fetch"
@get external status: response => int = "status"
@send external text: response => promise<string> = "text"
