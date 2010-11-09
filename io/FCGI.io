
/*
 Io FastCGI

 TODO:
	- Check Role type
	- Abort, Unknown, GetValues*
	- EndRequests's FCGI_CANT_MPX_CONN, FCGI_OVERLOADED, FCGI_UNKNOWN_ROLE responses
	- Run as CGI
	- Run as server (with unix socket and tcp socket)
	- Throw away CFFI
	- Multiplexing
	- Testing

omf
*/

CFFI

appendProto(CFFI Types)


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



Structure serialize := method( self asBuffer )

FCGIHeader := Structure with(list("version", UByte),
				list("recordType", UByte),
				list("requestId", UShort),
				list("contentLength", UShort),
				list("paddingLength", UByte),
				list("reserved", UByte)
)


FCGIBeginRequestBody := Structure with(list("role", UShort),
					list("flags", UByte),
					list("reserved", Array with(UByte, 5))
)

/*
protocolStatus:
	FCGI_REQUEST_COMPLETE:	normal end of request.
	FCGI_CANT_MPX_CONN:	rejecting a new request. This happens when a Web server sends concurrent requests over one connection to an application that is designed to process one request at a time per connection.
	FCGI_OVERLOADED:	rejecting a new request. This happens when the application runs out of some resource, e.g. database connections.
	FCGI_UNKNOWN_ROLE:	rejecting a new request. This happens when the Web server has specified a role that is unknown to the application.
*/
FCGIEndRequestBody := Structure with(list("appStatus", UInt),
					list("protocolStatus", UChar),
					list("reserved", Array with(UByte, 3))
)

FCGIUnknownTypeBody := Structure with(list("recordType", UChar),
					list("reserved", Array with(UByte, 7))
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
		if(buf isError not,
			//buf foreach(v, debugLine(v asHex))

			s := FCGIHeader clone fromBuffer(buf, true)

			this := FCGIRecord clone
			this setVersion(s version value)
			this setRecordType(s recordType value)
			this setRequestId(s requestId value)
			this setContentLength(s contentLength value)
			this setPaddingLength(s paddingLength value)

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

		header := self header serialize
		header = header exSlice(0, header size)

		//header foreach(v, debugLine(v asHex))
		//self contentData foreach(v, debugLine(v asHex))

		if(socket write(header) isError not,
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

	header := method( FCGIHeader with(self version, self recordType, self requestId, self contentLength, self paddingLength) )
)


FCGIInputStream := Object clone do(

	init := method(
		self buffer := ""
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

		while(avail < count,

			conn read
			
		)

		s := buffer exSlice(0, count)
		buffer removeSlice(0, count - 1)

		s
	)

	append := method(data,
		buffer appendSeq(data)
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
		endRec := FCGIRecord clone setVersion(FCGI_VERSION_1) setRecordType(streamType) setRequestId(self req id << 8) setContentLength(data size << 8) setPaddingLength(0) setContentData(data)
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
		this stdin := FCGIInputStream with(conn, self)
		this stdout := FCGIOutputStream with(conn, self)
		this stderr := FCGIOutputStream with(conn, self) setStreamType(FCGI_STDERR)
		this data := FCGIInputStream with(conn, self)
		this connection := conn
		this
	)

	run := method(
		debugLine("[FCGI Request] run ...")

		result := self connection server getSlot("application") call(self)

		debugLine("[FCGI Request] ... run")

		FCGIEndRequestBody with(0, FCGI_REQUEST_COMPLETE) serialize
	)
)

FCGIConnection := Object clone do(

	requests := Map clone
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
				self unknownType(rec)
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

		endRec := FCGIRecord clone setVersion(FCGI_VERSION_1) setRecordType(FCGI_END_REQUEST) setRequestId(reqId << 8) setContentLength(endReqBody size << 8) setPaddingLength(0) setContentData(endReqBody)
		endRec write(self socket)

		self requests removeAt(reqId asString)

		debugLine("[FCGI Connection] ... END_REQUEST")

		self
	)

	unknownType := method(rec,
		debugLine("[FCGI Connection] UNKNOWN ...")

		unkBody := FCGIUnknownTypeBody with(rec recordType) serialize

		rec setVersion(FCGI_VERSION_1) setRecordType(FCGI_UNKNOWN_TYPE) setRequestId(0) setContentLength(unkBody size << 8) setPaddingLength(0) setContentData(unkBody)
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
		//debugLine("[FCGI Connection] " .. rec contentData asString)

		br := FCGIBeginRequestBody clone fromBuffer(rec contentData, true)
		req := FCGIRequest with(self)
		req setId(rec requestId)
		req setRole(br role value)
		req setFlags(br flags value)

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
		//debugLine("[FCGI Connection] " .. rec asString)

		if(self requests size > 0,
			req := self requests at(rec requestId asString)
			//debugLine("[FCGI Connection] " .. req asString)

			if(rec contentData isNil not,
				decodeParams(req, rec contentData)
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
			return req
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

			//debugLine(next .. " param " .. k .. "=" .. v)

			req env atPut(k, v)

			next = next + vLen
		)

		//debugLine(req asString)

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
