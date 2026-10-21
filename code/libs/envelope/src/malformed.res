type step = Field(string) | Index(int) | Key(string)

type t = {at: array<step>, expected: string}
