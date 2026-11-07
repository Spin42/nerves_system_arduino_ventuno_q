# Prints the checksum Nerves records in an artifact's CHECKSUM file
# (Nerves.Artifact.checksum/1) for the package at the given path.
[path] = System.argv()
Mix.start()

files =
  Mix.Project.in_project(:toolchain, path, fn _ ->
    Mix.Project.config()[:nerves_package][:checksum]
  end)

files
|> Enum.flat_map(fn file ->
  full = Path.join(path, file)
  if File.dir?(full), do: Path.wildcard(Path.join(full, "**")), else: [full]
end)
|> Enum.map(&Path.expand/1)
|> Enum.filter(&File.regular?/1)
|> Enum.uniq()
|> Enum.map(&:crypto.hash(:sha256, File.read!(&1)))
|> then(&:crypto.hash(:sha256, &1))
|> Base.encode16()
|> IO.puts()
