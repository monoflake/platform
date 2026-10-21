# The machine driver's images, each built for every architecture a machine runs, RFC vr5lw.

variable "REGISTRY" {
	default = ""
}

group "default" {
	targets = ["workerd", "wasmtime"]
}

target "workerd" {
	context = "workerd"
	platforms = ["linux/amd64", "linux/arm64"]
	tags = ["${REGISTRY}workerd"]
}

target "wasmtime" {
	context = "wasmtime"
	platforms = ["linux/amd64", "linux/arm64"]
	tags = ["${REGISTRY}wasmtime"]
}
