# Creating a Simple Threading Utility for the ZX Spectrum

## Introduction

I thought it would be interesting to re-implement something similar to the `setjmp()` example that we reviewed in class in a more low-level setting.
I have had prior experience with Z80 assembly, so it seemed like a good fit for the project.
The system I chose to work with was the ZX Spectrum, a home computer system that was extremely popular in the 90's.
It is based on the Z80, and has a rather large hobbyist community around it, so it is a very well-documented system to begin with.

For the system to routinely take back control from the current program, we need to be able to make use of interrupts of some kind.
The Z80 includes maskable interrupts, but the hardware of the Spectrum creates some interesting challenges when attempting to insert our own code in place of the spectrum.

## Interrupts on the Z80

The Z80 has three interrupt modes: IM0, IM1, and IM2.
Each mode works as follows:

In IM0, when an interrupt mode is triggered, the CPU reads and executes an instruction from the data bus.
The Spectrum leaves the data bus pins disconnected, however, so this is not of much use to us.

IM1 acts as a simple `jp $0038` when triggered.
On the spectrum, this maps to a routine in ROM that handles screen updates during the vblank period, which is triggered at a rate of 50 times per second.
We have no way of modifying this code, short of physically replacing the ROM, so this is out of the question as well.

Lastly is IM2, the most complicated and also most versatile of the three modes.
When this mode is triggered, the CPU reads a 16-bit address from a lookup table and jumps to that address.
The MSB of this address is determined by the interrupt vector `i`, which exists as a register in the CPU.
The LSB is still fed over the bus, however.

Since we don't have control over the bus, the lower portion of the address will be effectively random.
However, since we do have some control over at least the upper portion, so we can specify an address by filling a 257-byte block with the same value, so no matter what value is read for the lower portion, the read result will be the same value.
We are restricted to jumping to addresses with the same byte in the LSB and MSB, but putting a `JP` at that address allows us take the control flow anywhere we want.

If we don't want to build a 257-byte table ourselves, we can take advantage of a preexisting one at `$C900`.
This table is full of `$FF`, however, so we end up jumping to `$FFFF`, leaving room for only a single byte before the control flow overflows back into ROM.
Fortunately, we can set this value to the beginning of a `jr` relative jump instruction, and the value in ROM at `$0000` lines up to result in a relative jump backwards to `$FFF4`, where we have enough room to place a full `jp`.
The execution of the `jr` uses up 12 clock cycles, but this seems like a worthy trade off in terms of memory saved.

## Managing the Threads

Now that we have a way of taking control, there comes the question of how the thread state is stored and recovered.
The Z80 has 18 8-bit registers, as well as two 8-bit flag registers and a 16-bit program counter and stack pointer that all need to be saved and restored whenever a context switch takes place.
We can solve this problem in a rather elegant way: Since the stack is unique to the current running thread, and it will not be used for anything until the context is restored, we can simply push all of the registers to it and then pop them off again later.
This greatly simplifies the actual mechanics of the interrupt system, since we only have to keep track of the stack pointers of waiting threads.

Once we have a way to start and save threads onto their stacks, the entire queue system simplifies down to a FIFO queue with the RR scheduling policy.
This is mildly difficult to implement on such a slow level, since we would have to shift the entire queue on a read, otherwise it would end up "walking" off into forbidden memory.
By restricting the maximum size of the queue, however, we can wrap the memory it occupies into a circular queue, distorting the address space so that its walk will never take it anywhere substantial.
This is extremely easy to implement in assembly: we simply only modify the lower byte of the head and tail pointers, creating a closed loop of 256 bytes, which can hold up to 128 separate stack pointers.

The procedure from here on out is trivial.
When a thread is created with a specified `sp` and `pc`, we prepare the stack with dummy variables, and append it to the queue.
To preform a context switch, we simply push all of the registers of the current thread to the stack, swap out our stack pointer for the one at the head of the FIFO queue, and restore everything to run the thread.
We append the old `SP` to the back of the queue if it is to be rerun, but if the thread is to be killed, we simply drop it.

## Conclusion

In the end, I was able to create a simple multiplexing with complete transparency outside of critical sections, aside from the slowdown inherent to the RR scheduling policy.
I feel positive about these results, and I'm very happy with the completeness of the layer of abstraction put into place here.

In this implementation, locking is implemented by disabling and re-enabling interrupts globally.
However, if the lock is held for too long, interrupts will start getting dropped.
This will have detrimental effects on the overall feel of the system, since the ROM routines and therefore the responsiveness of the system in general is highly dependent on the frequency at which interrupts routinely occur.
Fortunately, I've found that interrupts don't need to be used as frequently as one would expect as the Z80's diverse instruction set provides many atomic operations that would otherwise require the use of a mutex, the `inc (hl)` and `dec (hl)` operations having by far the most utility.
