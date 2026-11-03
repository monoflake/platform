/***
 * What the tests cast between the Fetch API's types and the Worker's abstract ones.
 */
let asFetcher: Web.fetch => Worker.fetcher = %raw(`fetch => ({fetch})`)
external asRequest: Web.request => Worker.request = "%identity"
external ofResponse: Worker.response => Web.response = "%identity"
