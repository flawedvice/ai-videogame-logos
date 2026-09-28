import time
import sys


def main():
    with open("devlog.txt", "a") as f:
        msg = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] " + " ".join(sys.argv[1:]) + "\n"
        f.write(msg)
        f.close()


if __name__ == "__main__":
    main()
