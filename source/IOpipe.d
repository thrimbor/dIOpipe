module dIOpipe.IOpipe;

/* TODO:
 * - improved unittests
 * - support for more operating systems (OS X, BSD)
 * - better error-handling
 */

import std.conv;

version (linux)
{
    
    import core.stdc.stdlib;
	import core.sys.posix.unistd;
    import std.file;
}
version (Windows)
{
    import core.sys.windows.windows;
	import std.stdio;
}

class PipeOpenError : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

class PipeReadError : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

class PipeWriteError : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

class IOpipe
{
    public:
        this (string executable, string workingDir = "")
        {
            version(linux)
            {
                int[2] pipeStdin;
                int[2] pipeStdout;

                if ((pipe(pipeStdin) != 0) || (pipe(pipeStdout) != 0))
                {
                    // error
					throw new PipeOpenError("");
                }

                if (fork() == 0)
                {
                    // child process
                    close(pipeStdin[1]);
                    close(pipeStdout[0]);

                    dup2(pipeStdin[0], 0);
                    dup2(pipeStdout[1], 1);

                    if (workingDir != "")
                        chdir(workingDir);

                    execl("/bin/sh".ptr, "sh".ptr, "-c".ptr, executable.ptr, cast(char*)0);
                    exit(1);
                }

                this.pipeStdin = pipeStdin[1];
                this.pipeStdout = pipeStdout[0];
                close(pipeStdin[0]);
                close(pipeStdout[1]);
            }

			version(Windows)
			{
				// set up pipe handle inheritance
				SECURITY_ATTRIBUTES sa;
				sa.nLength = SECURITY_ATTRIBUTES.sizeof;
				sa.lpSecurityDescriptor = null;
				sa.bInheritHandle = true;

				HANDLE hReadChildPipe, hWriteChildPipe;
				if (CreatePipe(&hReadChildPipe, &this.pipeStdin, &sa, 0) == 0)
				{
					// error, use GetLastError & friends and throw exception
				}
					
				if (CreatePipe(&this.pipeStdout, &hWriteChildPipe, &sa, 0) == 0)
				{
					// error, use GetLastError & friends and throw exception
				}

				// ensure that the stdin write pipe handle is not inherited
				if (SetHandleInformation(this.pipeStdin, HANDLE_FLAG_INHERIT, 0) == 0)
				{
					// error, use GetLastError & friends and throw exception
				}

				// ensure that the stdout read pipe handle is not inherited
				if (SetHandleInformation(this.pipeStdout, HANDLE_FLAG_INHERIT, 0) == 0)
				{
					// error, use GetLastError & friends and throw exception
				}


				STARTUPINFOA si;
				GetStartupInfoA(&si);
				//si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
				si.dwFlags |= STARTF_USESTDHANDLES;
				si.wShowWindow = SW_HIDE;
				si.hStdOutput = hWriteChildPipe;
				si.hStdError = hWriteChildPipe;
				si.hStdInput = hReadChildPipe;

				PROCESS_INFORMATION pi;
				if (CreateProcessA(cast(const(char)*)0, cast(char*)executable.ptr, null, null, true, CREATE_NEW_CONSOLE, null, null, &si, &pi) == 0)
				{
					// error, use GetLastError & friends and throw exception
				}

				CloseHandle(hWriteChildPipe);
				CloseHandle(hReadChildPipe);
			}
        }

        ~this ()
        {
            version(linux)
            {
                close(this.pipeStdin);
                close(this.pipeStdout);
            }
			
			version(Windows)
			{
				//TerminateProcess(hProcessHandle, 0);
				CloseHandle(this.pipeStdin);
				CloseHandle(this.pipeStdout);
			}
        }

        string read ()
        {
            version(linux)
            {
                char[4096] buf;
				auto amount = cast(int)core.sys.posix.unistd.read(this.pipeStdout, buf.ptr, 512);
				if (amount < 0)
					throw new PipeReadError("");

				return to!string(buf[0 .. amount]);
            }

			version(Windows)
			{
				char[512] buf;
				uint bytesRead;
				if (ReadFile(this.pipeStdout, cast(void*)buf.ptr, 512, &bytesRead, cast(LPOVERLAPPED)0) == 0)
				{
					// a real error occured - throw exception
				}
				
				if (bytesRead > 0)
					return to!string(buf);

				return "";
			}
        }

        size_t write (string wr)
        {
            version(linux)
            {
                //alias core.sys.posix.unistd.write writePipe;
				size_t totalBytesWritten = 0;
				size_t totalLength = wr.length;

				while (totalBytesWritten < totalLength)
				{
					size_t bytesWritten = core.sys.posix.unistd.write(this.pipeStdin, wr.ptr, wr.length);
					if (bytesWritten == -1)
					{
						throw new PipeWriteError("");
					}

					totalBytesWritten += bytesWritten;
					wr = wr[totalBytesWritten .. $];
				}

				return totalBytesWritten;
            }
			
			version(Windows)
			{
				uint bytesWritten;
				if (WriteFile(this.pipeStdin, wr.ptr, wr.length, &bytesWritten, cast(LPOVERLAPPED)0) == 0)
				{
					// a real error occured - throw exception
				}
			}
        }

    private:
        version(linux)
        {
            int pipeStdin, pipeStdout;
        }
		version(Windows)
		{
			HANDLE pipeStdin, pipeStdout;
		}
}

unittest
{
    version(linux)
	{
		import std.stdio;
	    auto io = new IOpipe("uname -a");

	    for (;;)
	    {
	        string msg = io.read();
	        if (msg == "") break;
	        writeln("-> " ~ msg);
	    }
	}

	version(Windows)
	{

		import std.stdio;
		import core.thread;
		auto io = new IOpipe("cmd.exe");

		io.write("help\r\n");

		Thread.sleep(dur!("seconds")(2));

		for (;;)
		{
			string l = io.read();
			writeln("-> " ~ l);

			if (l == "") break;
		}
	}
}
