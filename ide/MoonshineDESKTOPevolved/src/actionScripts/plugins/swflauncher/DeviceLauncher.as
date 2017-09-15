////////////////////////////////////////////////////////////////////////////////
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
// http://www.apache.org/licenses/LICENSE-2.0 
// 
// Unless required by applicable law or agreed to in writing, software 
// distributed under the License is distributed on an "AS IS" BASIS, 
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and 
// limitations under the License
// 
// No warranty of merchantability or fitness of any kind. 
// Use this software at your own risk.
// 
////////////////////////////////////////////////////////////////////////////////
package actionScripts.plugins.swflauncher
{
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.IOErrorEvent;
	import flash.events.NativeProcessExitEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.utils.IDataInput;
	import flash.utils.IDataOutput;
	
	import actionScripts.events.GlobalEventDispatcher;
	import actionScripts.plugin.actionscript.as3project.vo.AS3ProjectVO;
	import actionScripts.plugin.console.ConsoleOutputter;
	import actionScripts.plugin.core.compiler.CompilerEventBase;
	import actionScripts.valueObjects.Settings;

	public class DeviceLauncher extends ConsoleOutputter
	{
		private var customProcess:NativeProcess;
		private var customInfo:NativeProcessStartupInfo;
		private var queue:Vector.<Object> = new Vector.<Object>();
		private var isAndroid:Boolean;
		private var isRunAsDebugger:Boolean;
		
		public function DeviceLauncher()
		{
		}
		
		public function runOnDevice(project:AS3ProjectVO, sdk:File, swf:File, descriptorPath:String, runAsDebugger:Boolean=false):void
		{
			isAndroid = (project.buildOptions.targetPlatform == "Android");
			isRunAsDebugger = runAsDebugger;
			
			var descriptorPathModified:Array = descriptorPath.split(File.separator);
			
			// STEP 1
			var executableFile:File = (Settings.os == "win") ? new File("c:\\Windows\\System32\\cmd.exe") : new File("/bin/bash");
			
			customInfo = new NativeProcessStartupInfo();
			customInfo.executable = executableFile;
			customInfo.workingDirectory = swf.parent;
			
			addToQueue({com:"set FLEX_HOME="+ sdk.nativePath, showInConsole:false});
			addToQueue({com:"adt -package -target apk -storetype pkcs12 -keystore "+ project.buildOptions.certAndroid +" -storepass "+ project.buildOptions.certAndroidPassword +" "+ project.name +".apk" +" "+ descriptorPathModified[descriptorPathModified.length-1] +" "+ swf.name, showInConsole:true});
			addToQueue({com:"adt -installApp -platform android -package "+ project.name +".apk", showInConsole:true});
			
			startShell(true);
			
			flush();
		}
		
		private function addToQueue(value:Object):void
		{
			queue.push(value);
		}
		
		private function flush():void
		{
			if (queue.length == 0) 
			{
				startShell(false);
				return;
			}
			
			if (queue[0].showInConsole) debug("Sending to adt: %s", queue[0].com);
			
			var input:IDataOutput = customProcess.standardInput;
			input.writeUTFBytes(queue[0].com +"\n");
			queue.shift();
		}
		
		private function startShell(start:Boolean):void 
		{
			if (start)
			{
				customProcess = new NativeProcess();
				customProcess.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, shellData);
				customProcess.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, shellError);
				customProcess.addEventListener(IOErrorEvent.STANDARD_ERROR_IO_ERROR, shellError);
				customProcess.addEventListener(IOErrorEvent.STANDARD_OUTPUT_IO_ERROR, shellError);
				customProcess.addEventListener(NativeProcessExitEvent.EXIT, shellExit);
				customProcess.start(customInfo);
			}
			else
			{
				if (!customProcess) return;
				if (customProcess.running) customProcess.exit();
				customProcess.removeEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, shellData);
				customProcess.removeEventListener(ProgressEvent.STANDARD_ERROR_DATA, shellError);
				customProcess.removeEventListener(IOErrorEvent.STANDARD_ERROR_IO_ERROR, shellError);
				customProcess.removeEventListener(IOErrorEvent.STANDARD_OUTPUT_IO_ERROR, shellError);
				customProcess.removeEventListener(NativeProcessExitEvent.EXIT, shellExit);
				customProcess = null;
			}
		}
		
		private function shellError(e:ProgressEvent):void 
		{
			if (customProcess)
			{
				var output:IDataInput = customProcess.standardError;
				var data:String = output.readUTFBytes(output.bytesAvailable);
				
				var syntaxMatch:Array;
				var generalMatch:Array;
				var initMatch:Array;
				
				syntaxMatch = data.match(/(.*?)\((\d*)\): col: (\d*) Error: (.*).*/);
				if (syntaxMatch) {
					var pathStr:String = syntaxMatch[1];
					var lineNum:int = syntaxMatch[2];
					var colNum:int = syntaxMatch[3];
					var errorStr:String = syntaxMatch[4];
				}
				
				generalMatch = data.match(/(.*?): Error: (.*).*/);
				if (!syntaxMatch && generalMatch)
				{ 
					pathStr = generalMatch[1];
					errorStr  = generalMatch[2];
					pathStr = pathStr.substr(pathStr.lastIndexOf("/")+1);
					debug("%s", data);
				}
				else if (!isRunAsDebugger)
				{
					debug("%s", data);
				}
				
				startShell(false)
			}
		}
		
		private function shellExit(e:NativeProcessExitEvent):void 
		{
			if (customProcess) 
			{
				GlobalEventDispatcher.getInstance().dispatchEvent(new CompilerEventBase(CompilerEventBase.STOP_DEBUG,false));
			}
		}
		
		private function shellData(e:ProgressEvent):void 
		{
			var output:IDataInput = customProcess.standardOutput;
			var data:String = output.readUTFBytes(output.bytesAvailable);
			var match:Array;
			
			match = data.match(/set FLEX_HOME/);
			if (match)
			{
				flush();
				return;
			}
			
			match = data.match(/The application has been packaged with a shared runtime/);
			if (match) 
			{
				print("NOTE: The application has been packaged with a shared runtime.");
				flush();
				return;
			}
		}
	}
}