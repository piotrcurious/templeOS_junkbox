 To port GCC to TempleOS as a distcc node, you're not building GCC to compile for TempleOS, but rather building GCC to run on TempleOS and compile for another target, e.g. Linux. That means:

You’re running GCC on TempleOS (HolyC kernel + shell), but…

The code it produces is for a remote system, like Linux/x86-64.

TempleOS acts as a compute node in a distcc cluster, serving compile requests.


This is extremely non-trivial because TempleOS is not POSIX, lacks multitasking, has no TCP/IP stack, and has no conventional fork()/exec() system. So it cannot directly run distccd, nor easily host a modern GCC toolchain compiled for itself.

But here’s how you could theoretically achieve this, step by step:


---

✅ Conceptual Approach

Instead of porting GCC to TempleOS in the normal sense, cross-compile a Linux-targeting GCC, then wrap it in an RPC-style HolyC interface so TempleOS can:

1. Accept a compile request (via file on disk, serial port, or a RAM interface),


2. Spawn the cross-compiler with specific arguments (via HolyC),


3. Return the result.



You’ll be offloading compile tasks to TempleOS, but TempleOS itself won’t understand the binaries it runs.


---

🧩 Required Components

Component	Strategy

GCC (Linux-targeting)	Cross-compiled with a minimal runtime (no libc) for TempleOS
Host I/O	Use shared folder, serial link, or disk polling to send/receive files
Process launching	Implement a distccd shim in HolyC that: loads .TOS GCC binary, passes args, waits for output
Network protocol	Avoid real TCP/IP. Use shared drive polling or serial protocol to simulate request/response
Compiler format	Must be compiled into TempleOS-compatible flat binaries, e.g., using a Linux-hosted cross-compiler targeting templeos-flat



---

🔧 Step-by-Step Port Plan

1. Cross-Compile GCC for TempleOS Host

You'll need GCC compiled as a freestanding TempleOS executable, but targeting another platform (e.g., x86_64-linux-gnu):

./configure --target=x86_64-linux-gnu \
            --host=x86_64-templeos \
            --disable-shared \
            --disable-threads \
            --disable-nls \
            --disable-libstdc++ \
            --without-headers

Compile with a TempleOS-compatible backend (flat binary, no libc, static only). Output should be a .TOS binary that can be loaded and executed by HolyC.

> ⚠️ You may have to strip GCC features heavily. Use cc1, as, and ld separately instead of the full driver if needed.




---

2. Simulate a Network Layer

TempleOS has no TCP/IP, but you can simulate network input/output by:

Using a FAT32 shared disk between TempleOS and Linux host (e.g., via QEMU shared folder)

Or via a serial port or QEMU’s virtio-serial device


Implement a loop in TempleOS that does:

while (TRUE) {
  If (FileExists("DISTCC_REQ.TMP")) {
    // Read compile args from file
    // Call compiled GCC binary
    // Write result object file and DISTCC_RESP.TMP
  }
}

This can simulate a distccd behavior: files go in, GCC is called, files go out.


---

3. HolyC GCC Runner Shim

You’ll need a HolyC script (DistCCServer.HC) like:

U0 RunDistccTask() {
  Str args = FileRead("DISTCC_REQ.TMP");
  Print("Compiling: %s\n", args);
  Cmd(args); // Call to GCC.TOS with args
  FileWrite("DISTCC_RESP.TMP", "OK");
}

You can even boot into this directly by editing TempleOS/AutoExec.HC.


---

4. Client-Side Distcc Configuration

On the Linux client:

Create a fake distccd entry that writes the compile request to the shared folder.

Wait for DISTCC_RESP.TMP to appear.

Fetch the resulting object file.


Script example (Linux):

echo "gcc -O2 -c foo.c -o foo.o" > /mnt/templeos/DISTCC_REQ.TMP
while [ ! -f /mnt/templeos/DISTCC_RESP.TMP ]; do sleep 0.1; done
cp /mnt/templeos/foo.o ./build/


---

🧪 Testing It

1. Run TempleOS in QEMU, enable a shared drive.


2. Copy GCC.TOS and your HolyC runner script to TempleOS.


3. Start HolyC server loop.


4. From the host: drop a .c file and compile command into the shared folder.


5. Observe GCC run in TempleOS and return the compiled .o.




---

🚧 Major Limitations

TempleOS is single-threaded and non-preemptive — no concurrency.

No networking → only local or emulated transport is viable.

GCC and binutils must be statically linked and massively trimmed down.

No fork, exec, pipes, signals, etc.

Only one compile at a time (unless you hack in multiboot loops).



---

✅ Alternatives (If You're Pragmatic)

Use TempleOS only as a demo distcc node, not in production.

Run a minimal distccd proxy in Linux/QEMU, and delegate actual compile to TempleOS via expect/cmd.



---

📦 Summary

Step	Description

1	Cross-compile GCC targeting Linux but running on TempleOS
2	Build a file-based shim in HolyC to accept compile tasks
3	Simulate networked distcc via shared drive or serial
4	Use the client system to enqueue/dequeue compile tasks
5	Compile .c files on TempleOS, return .o via shared folder



---

If you want, I can help you create:

A minimal GCC toolchain tailored for TempleOS runtime.

A working QEMU-based shared folder setup.

A HolyC command processor that wraps cc1-style compile steps.


Let me know how far you want to go with this.

