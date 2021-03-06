/*
 Io FastCGI

 TODO:
	- EndRequests's FCGI_OVERLOADED responses
	- Run as CGI
	- Multiplexing
	- Testing

omf
*/
Protos Addons FCGI FCGI := Protos Addons FCGI

Socket

debugFile := nil
initDebug := method(fileName,
	debugFile = File with(fileName) remove openForAppending
	debugFile writef := method(self performWithArgList("write", call message argsEvaluatedIn(call sender)); self flush)
)
debugLine := method(seq, debugFile ?writef(seq asString .. "\n") )


FCGI_LISTENSOCK_FILENO	:=	0

FCGI_HEADER_LEN		:=	8

FCGI_VERSION_1		:=	1

FCGI_BEGIN_REQUEST	:=	1
FCGI_ABORT_REQUEST	:=	2
FCGI_END_REQUEST	:=	3
FCGI_PARAMS		:=	4
FCGI_STDIN		:=	5
FCGI_STDOUT		:=	6
FCGI_STDERR		:=	7
FCGI_DATA		:=	8
FCGI_GET_VALUES		:=	9
FCGI_GET_VALUES_RESULT	:=	10
FCGI_UNKNOWN_TYPE	:=	11
FCGI_MAXTYPE		:=	FCGI_UNKNOWN_TYPE

FCGI_NULL_REQUEST_ID	:=	0

FCGI_KEEP_CONN		:=	1

FCGI_RESPONDER		:=	1
FCGI_AUTHORIZER		:=	2
FCGI_FILTER		:=	3

FCGI_REQUEST_COMPLETE	:=	0
FCGI_CANT_MPX_CONN	:=	1
FCGI_OVERLOADED		:=	2
FCGI_UNKNOWN_ROLE	:=	3


FCGIHeaderFormat := "*BBHHBB"
FCGIBeginRequestBodyFormat := "*HB5B"
FCGIEndRequestBodyFormat := "*IB3B"
FCGIUnknownTypeBodyFormat := "*B7B"



Sequence fcgiDecodePairs := method(
	next := 0
	kLen := 0
	vLen := 0
	k := nil
	v := nil
	off := 1
	params := Map clone

	while(next < self size,
		v = ""
		off = 1

		kLen = self at(next)
		if((kLen & 0x80) == 0x80,
			kLen = ((kLen & 0x7f) << 24)
			kLen = kLen + (self at(next + 1) << 16)
			kLen = kLen + (self at(next + 2) << 8)
			kLen = kLen + self at(next + 3)
			off = 4
		)
			
		next = next + off
		
		vLen = self at(next)
		if((vLen & 0x80) == 0x80,
			vLen = ((vLen & 0x7f) << 24)
			vLen = vLen + (self at(next + 1) << 16)
			vLen = vLen + (self at(next + 2) << 8)
			vLen = vLen + self at(next + 3)
			off = 4
		,
			off = 1
		)

		next = next + off + kLen
		k = self exSlice(next - kLen, next)
		if(vLen, v = self exSlice(next, next + vLen))

		//debugLine(next .. " param " .. k .. "=" .. v)

		params atPut(k, v)

		next = next + vLen
	)

	params
)


Map fcgiEncodePairs := method(
	s := Sequence clone setItemType("uint8") setEncoding("number")

	self foreach(k, v,
		kLen := k size
		vLen := v size
		if(kLen > 255,
			s appendSeq(Sequence pack("*I", kLen | 0x80000000))
		,
			s append(kLen)
		)

		if(vLen > 255,
			s appendSeq(Sequence pack("*I", vLen | 0x80000000))
		,
			s append(vLen)
		)

		s appendSeq(k)
		s appendSeq(v)
	)

	s
)


FCGIException := Exception clone do(
	record ::= nil
	socketError ::= Error clone
)


FCGIRecord := Object clone do(
	version ::= 0
	recordType ::= 0
	requestId ::= 0
	contentLength ::= 0
	paddingLength ::= 0
	contentData ::= nil

	read := method(socket,
		debugLine("[FCGI Record] reading ...")

		buf := socket readBytes(FCGI_HEADER_LEN)
		if(buf isError,
			FCGIException setRecord(self) setSocketError(buf) raise("Record read")
		)

		//buf foreach(v, debugLine(v asHex))

		s := buf unpack(FCGIHeaderFormat)

		this := FCGIRecord clone
		this setVersion(s at(0))
		this setRecordType(s at(1))
		this setRequestId(s at(2))
		this setContentLength(s at(3))
		this setPaddingLength(s at(4))

		//debugLine("[FCGI Record] read header: " .. this asString)

		if(this contentLength > 0,
			this contentData = socket readBytes(this contentLength)
		)

		if(this paddingLength > 0,
			socket readBytes(this paddingLength)
		)

		this
	)


	write := method(socket,
		debugLine("[FCGI Record] writing ...")
		self paddingLength = (-self contentLength) & 7

		hdr := self header

		//hdr foreach(v, debugLine(v asHex))
		//self contentData foreach(v, debugLine(v asHex))

		e := socket write(hdr)
		if(e isError,
			FCGIException setRecord(self) setSocketError(e) raise("Record write header")
		)

		if(self contentLength > 0,
			e = socket write(self contentData)
			if(e isError,
				FCGIException setRecord(self) setSocketError(e) raise("Record write content data")
			)
				
			if(self paddingLength > 0,
				debugLine("[FCGI Record] ... padding (" .. self paddingLength .. ") ...")
				s := Sequence clone setSize(self paddingLength)
				e = socket write(s)
				if(e isError,
					FCGIException setRecord(self) setSocketError(e) raise("Record write padding data")
				)
			)
		)
		
		debugLine("[FCGI Record] ... written")
	)

	header := method(Sequence clone pack(FCGIHeaderFormat, self version, self recordType, self requestId, self contentLength, self paddingLength, 0))
)


FCGIInputStream := Object clone do(

	eof ::= false

	init := method(
		self buffer := Sequence clone
		self
	)

	with := method(conn, req,
		this := FCGIInputStream clone
		this connection := conn
		this req := req
		this
	)

	avail := method(
		self buffer size
	)

	read := method(count,
		debugLine("[FCGI InputStream] reading " .. count .. " ...")

		while(avail < count and eof not,
			self connection read
		)

		if(avail < count, count = avail)

		s := self buffer exSlice(0, count)
		self buffer removeSlice(0, count - 1)

		s
	)

	append := method(data,
		debugLine("[FCGI InputStream] appending ...")
		self buffer appendSeq(data)
		debugLine("[FCGI InputStream] ... appending")
	)
)

FCGIOutputStream := Object clone do(

	streamType ::= FCGI_STDOUT
	
	init := method(
		self buffer := List clone
		self
	)

	with := method(conn, req,
		this := FCGIOutputStream clone
		this connection := conn
		this req := req
		this
	)

	write := method(data,
		endRec := FCGIRecord clone setVersion(FCGI_VERSION_1) setRecordType(streamType) setRequestId(self req id) setContentLength(data size) setPaddingLength(0) setContentData(data)
		endRec write(self connection socket)
		self
	)

	writef := method(data,
		self buffer append(data)
		self
	)

	flush := method(
		b := self buffer join
		self buffer empty
		self write(b)
		self
	)
)

FCGIRequest := Object clone do(
	id ::= -1
	role ::= -1
	flags ::= 0

	with := method(conn,
		this := FCGIRequest clone
		this env := Map clone
		this stdin := FCGIInputStream with(conn, this)
		this stdout := FCGIOutputStream with(conn, this)
		this stderr := FCGIOutputStream with(conn, this) setStreamType(FCGI_STDERR)
		this data := FCGIInputStream with(conn, this)
		this connection := conn
		this
	)

	run := method(
		debugLine("[FCGI Request] run ...")

		status := self connection server application(self)

		if(status isKindOf(Number) not, status = 0)

		debugLine("[FCGI Request] ... run")

		status
	)
)

FCGIConnection := Object clone do(

	with := method(socket, server,
		this := FCGIConnection clone
		this socket := socket
		this server := server 
		this requests := Map clone
		this
	)

	run := method(
		debugLine("[FCGI Connection] running ...")

		loop(
			if(self socket isOpen,
				debugLine("[FCGI Connection] ... read ...")
				e := try( self read )
				if(e,
					debugLine("[FCGI Connection] EXCEPTION #{e error} [#{e socketError message}]" interpolate)
					self socket close
					break
				)
			,
				debugLine("[FCGI Connection] OUT ...")
				break
			)
		)
		debugLine("[FCGI Connection] ... running")
		self
	)

	read := method(
		debugLine("[FCGI Connection] reading ...")

		rec := FCGIRecord clone read(self socket)

		debugLine("[FCGI Connection] exec'ing ...")

		type := _commands at(rec recordType asString)
		if(type isNil,
			self _unknownType(rec)
		,
			self performWithArgList(type, list(rec))
		)

		debugLine("[FCGI Connection] ... exec'ed")

		self
	)

	close := method(
		debugLine("[FCGI Connection] closing ...")
		self socket close
		debugLine("[FCGI Connection] ... closed")
	)

	//------------------------------
	//"private" slots
	//------------------------------

	_endRequest := method(req, appStatus, protocolStatus, remove,
		debugLine("[FCGI Connection] END_REQUEST ...")
		endReqBody := Sequence clone pack(FCGIEndRequestBodyFormat, appStatus, protocolStatus)
		endRec := FCGIRecord clone setVersion(FCGI_VERSION_1) setRecordType(FCGI_END_REQUEST) setRequestId(req id) setContentLength(endReqBody size) setPaddingLength(0) setContentData(endReqBody)
		endRec write(self socket)

		if(remove isNil or remove,
			self requests removeAt(req id asString)
		)

		debugLine("[FCGI Connection] ... END_REQUEST")

		self
	)

	_unknownType := method(rec,
		debugLine("[FCGI Connection] UNKNOWN ...")

		unkBody := Sequence clone pack(FCGIUnknownTypeBodyFormat, rec recordType)

		rec setVersion(FCGI_VERSION_1) setRecordType(FCGI_UNKNOWN_TYPE) setRequestId(0) setContentLength(unkBody size) setPaddingLength(0) setContentData(unkBody)
		rec write(self socket)

		debugLine("[FCGI Connection] ... UNKNOWN")

		self
	)

	_doRequest := method(req,
		appStatus := 0
		protocolStatus := FCGI_REQUEST_COMPLETE

		if(req role != FCGI_RESPONDER,
			protocolStatus = FCGI_UNKNOWN_ROLE
		,
			appStatus = req run
		)

		_endRequest(req, appStatus, protocolStatus)

		// mmm... close?
		if((req flags & FCGI_KEEP_CONN) == 0, self close)
	)


	_commands := Map with(FCGI_BEGIN_REQUEST asString, "_beginRequestCommand",
				FCGI_ABORT_REQUEST asString, "_abortRequestCommand",
				FCGI_PARAMS asString, "_paramsCommand",
				FCGI_STDIN asString, "_stdinCommand",
				FCGI_DATA asString, "_dataCommand",
				FCGI_GET_VALUES asString, "_getValuesCommand")


	_beginRequestCommand := method(rec,
		debugLine("[FCGI Connection] BEGIN_REQUEST ...")
		//debugLine("[FCGI Connection] " .. rec contentData asString)

		br := rec contentData unpack(FCGIBeginRequestBodyFormat)
		req := FCGIRequest with(self)
		req setId(rec requestId)
		req setRole(br at(0))
		req setFlags(br at(1))

		debugLine("[FCGI Connection] ... new request: " .. req asString)

		if(self requests hasKey(req id asString) not,
			self requests atPut(req id asString, req)
		,
			_endRequest(req, 0, FCGI_CANT_MPX_CONN, false)
		)
		self
	)

	_abortRequestCommand := method(rec,
		debugLine("[FCGI Connection] ABORT ...")

		_endRequest(self requests at(rec requestId asString), 0, FCGI_REQUEST_COMPLETE)

		debugLine("[FCGI Connection] ... ABORT")
	)

	_paramsCommand := method(rec,
		debugLine("[FCGI Connection] PARAMS ...")
		//debugLine("[FCGI Connection] " .. rec asString)

		if(self requests size > 0,
			req := self requests at(rec requestId asString)
			//debugLine("[FCGI Connection] " .. req asString)

			if(rec contentData isNil not,
				params := rec contentData fcgiDecodePairs
				
				if(params at("PATH_INFO") isEmpty,
					params atPut("PATH_INFO", params at("REQUEST_URI") beforeSeq("?"))
				)
				if(params at("QUERY_STRING") isEmpty,
					params atPut("QUERY_STRING", params at("REQUEST_URI") afterSeq("?"))
				)

				req env empty mergeInPlace(params)
			,
				//return req
				_doRequest(req)
			)
		)
		debugLine("[FCGI Connection] ... PARAMS")
		self
	)

	_stdinCommand := method(rec,
		debugLine("[FCGI Connection] STDIN ...")

		req := self requests at(rec requestId asString)

		if(rec contentLength > 0,
			req stdin append(rec contentData)
		,
			req stdin setEof(true)
		)
		debugLine("[FCGI Connection] ... STDIN")
		self
	)

	_dataCommand := method(rec,
		debugLine("[FCGI Connection] DATA ...")

		req := self requests at(rec requestId asString)

		if(rec contentLength > 0,
			req data append(rec contentData)
		,
			req data setEof(true)
		)
		debugLine("[FCGI Connection] ... DATA")
		self
	)

	_getValuesCommand := method(rec,
		debugLine("[FCGI Connection] GET_VALUES ...")

		pairs := Map clone
		p := self server params
		
		rec contentData fcgiDecodePairs foreach(k, v, if(p keys contains(k), pairs atPut(k, p at(k))))
		
		pairsSeq := pairs fcgiEncodePairs
		
		resp := FCGIRecord clone setVersion(FCGI_VERSION_1) setRecordType(FCGI_GET_VALUES_RESULT) setRequestId(FCGI_NULL_REQUEST_ID) setContentLength(pairsSeq size) setContentData(pairsSeq)
		resp write(self socket)

		debugLine("[FCGI Connection] ... GET_VALUES")
		self
	)
)

FCGIServer := Object clone do(

	params := Map with("FCGI_MAX_CONNS", 50,
			   "FCGI_MAX_REQS", 1,
			   "FCGI_MPXS_CONNS", false)

	maxConns := method(params at("FCGI_MAX_CONNS"))
	setMaxConns := method(maxConns, params atPut("FCGI_MAX_CONNS", maxConns) ; self)
	
	maxReqs := method(params at("FCGI_MAX_REQS"))
	setMaxReqs := method(self)

	isMultiplexed := method(params at("FCGI_MPXS_CONNS"))
	setMultiplexed := method(self)

	timeToRun ::= 3
	
	application := method(request, "Must provide an application(request) method to be executed by the server!!")

	run := method(address,
		wait(self timeToRun)
		
		debugLine("[FCGI Server] running ...")

		socket := nil

		if(address isNil,
			while(socket isError or socket isNil,
				wait(0.1)
				socket = Socket fromFd(FCGI_LISTENSOCK_FILENO, Socket AF_UNIX)
				if(socket isError,
					debugLine(socket message)
				,
					break
				)
			)
		,
			socket = Socket clone setAddress(address)
			socket serverOpen returnIfError
		)
		
		debugLine(socket isOpen asString)

		newSocket := nil
		loop(
			loop(
				debugLine("[FCGI Server] accepting ...")
				newSocket = socket serverWaitForConnection
				if(newSocket isError,
					debugLine(newSocket message)
					continue
				,
					break
				)
			)

			conn := FCGIConnection with(newSocket, self)

			//go, go, go!!!!
			conn @@run
		)
	)
)
