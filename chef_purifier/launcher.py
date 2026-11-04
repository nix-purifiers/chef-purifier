import os
import subprocess
import sys

from chef_purifier.main import main

sys.argv[0] = os.environ["CHEF_PURIFIER_COMMAND"]
try:
    main()
except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
    print(f"chef-purifier: {error}", file=sys.stderr)
    raise SystemExit(1)
