# What this machine's hardware asks, which `nixos-generate-config --no-filesystems` writes over
# this file, as nixos-anywhere's `--generate-hardware-config nixos-generate-config <this file>`
# runs it; its disk is disko's. It names the system and what the initrd needs to reach the disk.
# An x86_64 virtual machine's usually holds:
#   imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
#   boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_blk" ];
#   nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
# An arm64 one's, booting UEFI:
#   imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
#   boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_pci" "virtio_scsi" "usbhid" ];
#   nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
{ }
