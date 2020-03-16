;; Run this file with a WASI runtime:
;;   wasmer run fizzbuzz.wat
;;   wasmtime run fizzbuzz.wat
;; or compile it into binary:
;;   wasm-opt fizzbuzz.wat -Oz --converge --output fizzbuzz.wasm

(module
	;; Import a function from the WASI interface
	(func $fd_write (import "wasi_unstable" "fd_write") (param i32 i32 i32 i32) (result i32))

	;; The function exported as "_start" will be the entry point
	(func (export "_start") ;; () => void
		;; var $i
		(local $i i32)
		;; var $need_write_numeric
		;; There's no boolean type in WA. We use i32 instead
		(local $need_write_numeric i32)

		(loop $write_stuff
			;; $i = $i + 1
			(local.set $i
				(i32.add (local.get $i) (i32.const 1))
			)
			(local.set $need_write_numeric (i32.const 1))

			(if
				;; ($i % 3) == 0
				(i32.eqz (i32.rem_u (local.get $i) (i32.const 3)))
				(then
					(call $output_fizz)
					;; $need_write_numeric = 0
					(local.set $need_write_numeric (i32.const 0))
				)
			)

			(if
				;; ($i % 5) == 0
				(i32.eqz (i32.rem_u (local.get $i) (i32.const 5)))
				(then
					(call $output_buzz)
					(local.set $need_write_numeric (i32.const 0))
				)
			)

			(if (local.get $need_write_numeric)
				(then
					(call $output_numeric (local.get $i))
				)
			)

			(call $output_separator)

			(br_if $write_stuff
				;; $i < 100
				(i32.lt_u (local.get $i) (i32.const 100))
			)
		)
	)

	(func $output_fizz ;; () => void
		;; Ignore the result of the following expression.
		;; Normally the IO errors should be handled, but - nope, not this time!
		(drop
			;; Call a WASI function
			(call $fd_write
				;; File pointer. 1 is stdout, much like in POSIX
				(i32.const 1)
				;; Pointer to an input-output vector structure in memory
				;; (0x0010 + 0) stores a pointer to the string start
				;; (0x0010 + 4) stores the string length

				;; This data is hardcoded in (data) sections:
				;; Data at 0x0000 is a literal "Fizz" (4 bytes)
				;;           |                              |
				;;           +-----------------------v      |
				;; Data at 0x0010 contains a value 0x0000   |
				;; Data at 0x0014 contains a value 0x0004 <-+
				(i32.const 0x0010)
				;; This function may accept several iovec's at a time.
				;; And actually the first argument is the pointer to an
				;; *array of* iovecs, stored consecutively in the memory.
				;; But this time there's only one
				(i32.const 1)
				;; The function returns a number of bytes actually written.
				;; So far WA cannot return multiple values from a function.
				;; So we pass a pointer where that value will be written in
				;; memory. In this program we ignore it.
				;; But we still have to tell fd_write to write it somewhere.
				(i32.const 0x000c)
			)
		)
	)

	(func $output_buzz ;; () => void
		(drop
			(call $fd_write
				(i32.const 1) ;; stdout
				(i32.const 0x0018) ;; *iovec
				(i32.const 1) ;; iovec length
				(i32.const 0x000c) ;; *nwritten
			)
		)
	)

	(func $output_separator ;; () => void
		(drop
			(call $fd_write
				(i32.const 1) ;; stdout
				(i32.const 0x0020) ;; *iovec
				(i32.const 1) ;; iovec length
				(i32.const 0x000c) ;; *nwritten
			)
		)
	)

	(func $output_numeric (param $v i32) ;; (i32) => void
		;; Getting modulo 10 gives us one digit at a time
		;; We get those digits right-to-left, so we start from the end
		;; of the array and moving towards its start

		(local $len i32) ;; Length of the resulting string
		(local.set $len (i32.const 0))

		(loop $get_digit
			;; $len = $len + 1
			(local.set $len
				(i32.add (local.get $len) (i32.const 1))
			)

			(i32.store8
				;; 0x40 - $len
				(i32.sub (i32.const 0x0040) (local.get $len))
				;; The ASCII code for 0 is 0x30,
				;; for 1 it's 0x31, etc.
				;; We can easily convert a digit to ASCII adding 0x30

				;; ($v % 10) + 0x30
				(i32.add
					(i32.rem_u (local.get $v) (i32.const 10))
					(i32.const 0x30)
				)
			)

			;; $v = $v / 10
			(local.set $v
				(i32.div_u (local.get $v) (i32.const 10))
			)

			;; if ($v != 0) continue;
			(br_if $get_digit (local.get $v))
		)

		;; Update iovec.pointer in memory
		(i32.store (i32.const 0x0028)
			(i32.sub (i32.const 0x0040) (local.get $len))
		)
		;; Update iovec.length in memory
		(i32.store (i32.const 0x002c)
			(local.get $len)
		)

		(drop
			(call $fd_write
				(i32.const 1) ;; stdout
				(i32.const 0x0028) ;; *iovec
				(i32.const 1) ;; iovec length
				(i32.const 0x000c) ;; *nwritten
			)
		)
	)

	;; WASI requires the memory be exported as "memory"
	(memory (export "memory") 1)


	;; The hardcoded initial data.
	;; There's no "module level constants" in WAT, so we lay out the memory
	;; manually. :shrug:

	;; 0000...0003: Literal "fizz"
	;; 0004...0007: Literal "buzz"
	;; 0008...0009: Literal "\n"
	(data (i32.const 0x00) "Fizz")
	(data (i32.const 0x04) "Buzz")
	(data (i32.const 0x08) "\n")

	;; 000c...000f: fd_write nwritten
	;; Just reserved, no data

	;; 0010...0013: iovec.pointer for "fizz"
	;; 0014...0017: iovec.length for "fizz"
	(data (i32.const 0x10) "\00\00\00\00") ;; Little endian 0x0000
	(data (i32.const 0x14) "\04\00\00\00") ;; Little endian 0x0004

	;; 0018...001b: iovec.pointer for "buzz"
	;; 001c...001f: iovec.length for "buzz"
	(data (i32.const 0x18) "\04\00\00\00") ;; Little endian 0x0004
	(data (i32.const 0x1c) "\04\00\00\00") ;; Little endian 0x0004

	;; 0020...0023: iovec.pointer for ","
	;; 0024...0027: iovec.length for ","
	(data (i32.const 0x20) "\08\00\00\00") ;; Little endian 0x0008
	(data (i32.const 0x24) "\01\00\00\00") ;; Little endian 0x0002

	;; 0028...002b: iovec.pointer for numeric values
	;; 002c...002f: iovec.length for numeric values
	;; Just reserved, no data

	;; 0030...003f: memory for numeric values
	;; Just reserved, no data
)