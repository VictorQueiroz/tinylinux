const pkgName = process.argv[2];
const slices = pkgName.split("/");

let result;

if (slices.length === 0) {
  process.exitCode = 1;
  process.stderr.end(`Error: Invalid package name: ${pkgName}`);

  result = { repo: null, name: null };
} else if (slices.length === 1) {
  result = { repo: null, name: slices[0] };
} else {
  result = { repo: slices[0], name: slices[slices.length - 1] };
}

process.stdout.end(JSON.stringify(result));
