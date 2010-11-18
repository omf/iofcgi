#!/usr/local/bin/io

doRelativeFile("FCGI.io")

//l := initDebug("/tmp/kk_" .. System thisProcessPid .. ".log")
l := initDebug("/tmp/kk.log")

debugLine(System args size asString)
debugLine(System args at(0))

wait(3)

srv := FCGIServer clone do(

	application := method(req,
		debugLine(req asString)

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

		req stdout write("Status: 200 OK\r\nContent-Type: text/html\r\n\r\n")
		req stdout write("<html><head><title>testcgi</title></head><body>")
		req stdout write("")

		req env keys sort foreach(k, req stdout write(k .. "= " .. req env at(k) .. "<br>"))

		req stdout write("<hr>")
		req stdout write(s .. "<br>")

		req stdout write("<hr>")
		m keys sort foreach(k, req stdout write(k .. "= " .. m at(k) .. "<br>"))

		req stdout write("</body></html>")
		req stdout write("")

		0
	)

)

srv run


