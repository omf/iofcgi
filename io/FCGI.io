
/*
 Io FastCGI

 TODO:
	- Check Role type
	- Abort, Unknown, GetValues*
	- EndRequests's FCGI_CANT_MPX_CONN, FCGI_OVERLOADED, FCGI_UNKNOWN_ROLE responses
	- Run as CGI
	- Run as server (with unix socket and tcp socket)
	- Multiplexing
	- Testing

omf
*/

doRelativeFile("pack.io")


File writef := method(self performWithArgList("write", call message argsEvaluatedIn(call sender)); self flush)

initDebug := method(fileName,
	File with(fileName) remove openForAppending
)

debugLine := method(seq, l writef(seq asString .. "\n") )


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

FCGI_MAX_CONNS		:=	"FCGI_MAX_CONNS"
FCGI_MAX_REQS		:=	"FCGI_MAX_REQS"
FCGI_MPXS_CONNS		:=	"FCGI_MPXS_CONNS"



FCGIHeaderFormat := "*CCSSCC"
FCGIBeginRequestBodyFormat := "*SCC5"
FCGIEndRequestBodyFormat := "*ICC3"
FCGIUnknownTypeBodyFormat := "*CC7"


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
		if(buf isError not,
			buf foreach(v, debugLine(v asHex))

			s := buf unpack(FCGIHeaderFormat)

			this := FCGIRecord clone
			this setVersion(s at(0))
			this setRecordType(s at(1))
			this setRequestId(s at(2))
			this setContentLength(s at(3))
			this setPaddingLength(s at(4))

			debugLine("[FCGI Record] read header: " .. this asString)

			if(this contentLength > 0,
				this contentData = socket readBytes(this contentLength)
			)

			if(this paddingLength > 0,
				socket readBytes(this paddingLength)
			)

			return this
		)

		buf
	)


	write := method(socket,
		debugLine("[FCGI Record] writing ...")
		self paddingLength = (-self contentLength) & 7

		hdr := self header

		hdr foreach(v, debugLine(v asHex))
		self contentData foreach(v, debugLine(v asHex))

		if(socket write(hdr) isError not,
			if(self contentLength > 0,
				if(socket write(self contentData) isError,
					debugLine("[FCGI Record] ERROR 2")
				,
					if(self paddingLength > 0,
						debugLine("[FCGI Record] ... padding (" .. self paddingLength .. ") ...")
						s := Sequence clone setSize(self paddingLength)
						socket write(s)
					)
				)
			)
		,
			debugLine("[FCGI Record] ERROR 1")
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

	with := method(conn, req,
		this := FCGIOutputStream clone
		this connection := conn
		this req := req
		this
	)

	write := method(data,
		endRec := FCGIRecord clone setVersion(FCGI_VERSION_1) setRecordType(streamType) setRequestId(self req id) setContentLength(data size) setPaddingLength(0) setContentData(data)
		endRec write(self connection socket)
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

		result := self connection server application(self)

		debugLine("[FCGI Request] ... run")

		Sequence clone pack(FCGIEndRequestBodyFormat, 0, FCGI_REQUEST_COMPLETE)
	)
)

FCGIConnection := Object clone do(

	commands := Map with(FCGI_BEGIN_REQUEST asString, "_beginRequestCommand",
				FCGI_ABORT_REQUEST asString, "_abortRequestCommand",
				FCGI_PARAMS asString, "_paramsCommand",
				FCGI_STDIN asString, "_stdinCommand",
				FCGI_DATA asString, "_dataCommand",
				FCGI_GET_VALUES asString, "_getValuesCommand")

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
				self read
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
		if(rec isError not,
			debugLine("[FCGI Connection] exec'ing ...")

			req := self performWithArgList(commands at(rec recordType asString), list(rec))

			if(req isKindOf(FCGIRequest),

				endReqBody := req run
				endRequest(req id, endReqBody)

				if((req flags & FCGI_KEEP_CONN) == 0,
					self close
				)
			,
				if(req isNil,
					req println
					self unknownType(rec)
				)
			)

			debugLine("[FCGI Connection] ... exec'ed")

			return self
		)

		rec
	)


	close := method(
		debugLine("[FCGI Connection] closing ...")
		self socket close
		debugLine("[FCGI Connection] ... closed")
	)

	endRequest := method(reqId, endReqBody,
		debugLine("[FCGI Connection] END_REQUEST ...")

		endRec := FCGIRecord clone setVersion(FCGI_VERSION_1) setRecordType(FCGI_END_REQUEST) setRequestId(reqId) setContentLength(endReqBody size) setPaddingLength(0) setContentData(endReqBody)
		endRec write(self socket)

		self requests removeAt(reqId asString)

		debugLine("[FCGI Connection] ... END_REQUEST")

		self
	)

	unknownType := method(rec,
		debugLine("[FCGI Connection] UNKNOWN ...")

		unkBody := Sequence clone pack(FCGIUnknownTypeBodyFormat, rec recordType)

		rec setVersion(FCGI_VERSION_1) setRecordType(FCGI_UNKNOWN_TYPE) setRequestId(0) setContentLength(unkBody size) setPaddingLength(0) setContentData(unkBody)
		rec write(self socket)

		debugLine("[FCGI Connection] ... UNKNOWN")

		self
	)

	getValuesResult := method(rec,
		debugLine("[FCGI Connection] GET_VALUES_RESULT ...")
		debugLine("[FCGI Connection] ... GET_VALUES_RESULT")
	)





	_beginRequestCommand := method(rec,
		debugLine("[FCGI Connection] BEGIN_REQUEST ...")
		debugLine("[FCGI Connection] " .. rec contentData asString)

		br := rec contentData unpack(FCGIBeginRequestBodyFormat)
		req := FCGIRequest with(self)
		req setId(rec requestId)
		req setRole(br at(0))
		req setFlags(br at(1))

		debugLine("[FCGI Connection] ... new request: " .. req asString)

		self requests atPut(req id asString, req)
		self
	)

	_abortRequestCommand := method(rec,
		debugLine("[FCGI Connection] ABORT ...")

		debugLine("[FCGI Connection] ... ABORT")
	)

	_paramsCommand := method(rec,
		debugLine("[FCGI Connection] PARAMS ...")
		debugLine("[FCGI Connection] " .. rec asString)

		if(self requests size > 0,
			req := self requests at(rec requestId asString)
			debugLine("[FCGI Connection] " .. req asString)

			if(rec contentData isNil not,
				decodeParams(req, rec contentData)
				if(req env at("PATH_INFO") isEmpty,
					req env atPut("PATH_INFO", req env at("REQUEST_URI") beforeSeq("?"))
				)
				if(req env at("QUERY_STRING") isEmpty,
					req env atPut("QUERY_STRING", req env at("REQUEST_URI") afterSeq("?"))
				)
			,
				return req
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
		)
		debugLine("[FCGI Connection] ... DATA")
		self
	)

	_getValuesCommand := method(rec,
		debugLine("[FCGI Connection] GET_VALUES ...")
		debugLine("[FCGI Connection] ... GET_VALUES")
	)

	//TODO there are more encondings!!
	decodeParams := method(req, data,
		next := 0
		kLen := 0
		vLen := 0
		k := nil
		v := nil

		while(next < data size,
			kLen = data at(next)
			vLen = data at(next + 1)

			next = next + 2 + kLen
			k = data exSlice(next - kLen, next)
			v = data exSlice(next, next + vLen)

			debugLine(next .. " param " .. k .. "=" .. v)

			req env atPut(k, v)

			next = next + vLen
		)

		debugLine(req asString)

	)
)

FCGIServer := Object clone do(

	application := method(request, "Must provide an application(request) method to be executed by the server!!" ; exit )

	run := method(
		debugLine("[FCGI Server] running ...")

		socket := nil

		while(socket isError or socket isNil,
			wait(0.1)
			socket = Socket fromFd(FCGI_LISTENSOCK_FILENO, AddressFamily AF_UNIX)
			if(socket isError, debugLine(socket message), break)
		)

		debugLine(socket isOpen asString)

		loop(
			newSocket := nil
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
			conn @run
		)
	)
)
