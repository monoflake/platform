/***
 * An object served on the public socket, `GET /v1/storage/{bucket}/{object}` with the headers of
 * RFC 13ixj. The model's interface, `docs/code.md`.
 */

/**
 * `GET` answers the content, `HEAD` the same without a body, and an `If-None-Match` of the ETag
 * answers 304. Another method on such a path answers 405 and any other path 404; a name not
 * written answers 404, content lost 503, any other error 500.
 */
let fetch: (Operations.context, Web.request) => promise<Web.response>
