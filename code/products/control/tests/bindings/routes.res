let fetcher: Web.fetch => Web.fetcher = %raw(`fetch => ({fetch})`)

let bucket: unit => Stores.bucket = %raw(`() => {
  const held = new Map()
  return {
    put: async (name, bytes) => {held.set(name, bytes)},
    get: async name => {
      const bytes = held.get(name)
      return bytes ? {size: bytes.length, body: new Blob([bytes]).stream()} : null
    },
  }
}`)
