
/*
uint8 = C
int8 = c

uint16 = S
int16 = s

uint32 = I
int32 = i

uint64 = L
int64 = l

float32 = f

float64 = F
*/

Sequence packCodes := Map with("C","uint8", "c","int8", "S","uint16", "s","int16", "I","uint32", "i","int32", "L","uint64", "l","int64", "f","float32", "F","float64")

// naïve
Sequence unpack := method(format,

	aux := nil
	count := 0
	next := 0
	res := List clone
	item := nil
	i := 0
	bigEndian := false
	s := Sequence clone

	if(format at(0) asCharacter == "*", bigEndian = true ; i = 1)

	while(i < format size and next < self size,
		f := format at(i) asCharacter
		it := packCodes at(f)
		if(it isNil, return Error with("Unknown code in format: " .. f))
		s setItemType(it)

		aux = format at(i + 1)
		count = 1
		f = 0
		while(aux > 0x30 and aux < 0x39,
			f = (f * 10) + (aux - 0x30)
			count = f
			i = i + 1
			aux = format at(i + 1)
		)

		f = 0
		item = Sequence clone
		while(f < count,
			aux = next + s itemSize
			if(bigEndian and s itemSize > 1,
				item appendSeq(self exSlice(next, aux) reverse)
			,
				item appendSeq(self exSlice(next, aux))
			)
			next = aux
			f = f + 1
		)
		item setEncoding("number") setItemType(it)
		if(item size <= 1,
			item = item at(0)
		)
		res append(item)

		i = i + 1
	)

	res
)

Sequence pack := method(format, //values

	args := call message argsEvaluatedIn(call sender) reverse
	arg := args pop

	i := 0
	bigEndian := false
	aux := nil
	count := 0
	res := self clone setItemType("uint8") setEncoding("number")

	if(format at(0) asCharacter == "*", bigEndian = true ; i = 1)

	while(i < format size and args size > 0,
		arg = args pop
		if(arg isNil, return Error with("Number of arguments differ from format specifier"))

		f := format at(i) asCharacter
		it := packCodes at(f)
		if(it isNil, return Error with("Unknown code in format: " .. f))

		aux = format at(i + 1)
		count = 1
		f = 0
		while(aux > 0x30 and aux < 0x39,
			f = (f * 10) + (aux - 0x30)
			count = f
			i = i + 1
			aux = format at(i + 1)
		)
		
		f = 0
		temp := Sequence clone setEncoding("number")
		while(f < count,
			if(count == 1,
				temp empty setItemType(it) atPut(0, arg) setItemType("uint8")
			,
				temp empty setItemType(it) atPut(0, arg at(f)) setItemType("uint8")
			)
			if(bigEndian,
				res appendSeq(temp reverse)
			,
				res appendSeq(temp)
			)

			f = f + 1
		)
		i = i + 1

	)

	res
)


