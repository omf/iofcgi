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

		req stdout write("Status: 200 OK\r\nContent-Type: text/html\r\n\r\n")
		req stdout write("<html><head><title>testcgi</title></head><body>")
		req stdout write("TOMAaAAA!! QUE PACHAAAAAAA<br>")
		req stdout write("")

		req env foreach(k, v, req stdout write(k .. "= " .. v .. "<br>"))

		req stdout write("</body></html>")
		req stdout write("")
	)

)

srv run


