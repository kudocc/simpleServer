simpleServer
============

A simple echo server support standard input and customer protocol

The build target is moved to `~/Desktop/` , You can launch the application by input the `./server4Someday` in command line, it listens on 7001 port.

Once a client has connected, you can input some text through command line, it will send the text to client with specified text protocol, the text protocol is defined in NetworkHeader.h.

You can use [tcpClient](https://github.com/kudocc/tcpClient) to test with this server.
