import subprocess
import os

def run_git_cmd(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        return f"ERROR: {e.stdout}\n{e.stderr}"

print("Git Status:")
print(run_git_cmd(['git', 'status']))
print("\nGit Remote:")
print(run_git_cmd(['git', 'remote', '-v']))
print("\nGit Branch:")
print(run_git_cmd(['git', 'branch', '-v']))
