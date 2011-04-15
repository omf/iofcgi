#!/usr/local/bin/io

doRelativeFile("fcgi.io")

//l := initDebug("/tmp/kk_" .. System thisProcessPid .. ".log")
l := initDebug("/tmp/kk.log")

debugLine(System args size asString)
debugLine(System args at(0))

wait(3)

srv := FCGIServer clone do(

	application := method(req,
		//debugLine(req asString)
	
		req env keys sort foreach(k, debugLine(k .. "= " .. req env at(k)))
		s := Sequence clone

		if(req env at("REQUEST_METHOD") == "POST",
			debugLine("[FCGI Application] reading stdin ...")

			size := req env at("CONTENT_LENGTH")
			s appendSeq(req stdin read(size))

			//more := true
			//while(more,
			//	s appendSeq(req stdin read(20))
			//	if(req stdin avail <= 0, more = false)
			//)

			debugLine("AVAIL: " .. req stdin avail)
			debugLine("[FCGI Application] ... read stdin")
		)

		if(req env at("REQUEST_METHOD") == "GET",
			s := req env at("QUERY_STRING")
		)

		debugLine(s)
		m := CGI parseString(s)

		//wait(10)

		req stdout writef("Status: 200 OK\r\nContent-Type: text/html\r\n\r\n")
		req stdout writef("<html><head><title>testcgi</title></head><body>\r\n")

		req env keys sort foreach(k, wait(0.2);req stdout writef(k .. "= " .. req env at(k) .. "<br>\r\n");req stdout flush)

		req stdout writef("<hr>\r\n")
		req stdout writef(s .. "<br>\r\n")

		req stdout writef("<hr>\r\n")
		m keys sort foreach(k, req stdout writef(k .. "= " .. m at(k) .. "<br>\r\n"))

		req stdout writef("</body></html>")
		req stdout writef("")
		req stdout flush

		return 0
	)

)

srv run


