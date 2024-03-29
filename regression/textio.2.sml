(* Notice: This test will not be passed on platforms like Win32!
           But for Linux it happens to work... *)

fun testRange (start, length) =
      let
        val allChars = CharVector.tabulate(length, fn i => chr ((i + start) mod 256))

        val outStr = TextIO.openOut "testTextIO.txt"
        val _ = TextIO.output (outStr, allChars)
        val _ = TextIO.closeOut outStr
        
        val inStr = TextIO.openIn "testTextIO.txt"
        val readChars = TextIO.inputAll inStr
        val _ = TextIO.closeIn inStr
        
        fun testCharF (c, cnt) =
              let
                val readC = CharVector.sub(readChars, cnt)
                val _ = if c = readC then
                          ()
                        else
                          print ("Error at index: " ^ (Int.toString cnt) ^ ": " ^
                                 (Char.toString c) ^ " <> " ^ (Char.toString readC))
              in
                cnt + 1
              end
      
        val _ = CharVector.foldl testCharF 0 allChars
      in
        ()
      end

val _ = testRange (0, 256)
val _ = print "basic test of writing and reading back all characters done\n"
val _ = List.tabulate(256, fn i => List.tabulate(257, fn i2 => testRange (i, i2)))
val _ = print "test of writing files of all possible characters in strings of lengths 0-256 finished\n"
val _ = List.tabulate(6, fn i => List.tabulate(5000, fn i2 => testRange (i, i2)))

val _ = print "test finished\n"
