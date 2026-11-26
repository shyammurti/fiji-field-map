package net.homelab.offroad

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity(){
    override fun configureFlutterEngine(engine:FlutterEngine){
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger,"fieldmap/drive").setMethodCallHandler { call,result ->
            try { DriveJournal(this).use { journal ->
                when(call.method){
                    "status" -> result.success(mapOf("id" to journal.session(),"active" to (DriveService.running||DriveService.starting),"count" to journal.count(),"recent" to if(DriveService.running) journal.fixes(true) else emptyList<List<Number>>()))
                    "start" -> {
                        check(journal.session()==null){"Review the previous drive first"}
                        check(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED){"Allow precise location to record a drive"}
                        val id=UUID.randomUUID().toString()
                        journal.start(id)
                        DriveService.starting=true
                        try {
                            val intent=Intent(this,DriveService::class.java)
                            if(Build.VERSION.SDK_INT>=26)startForegroundService(intent) else startService(intent)
                        }catch(e:Exception){ DriveService.starting=false;journal.discard(id);throw e }
                        result.success(id)
                    }
                    "finish" -> { journal.stop();stopService(Intent(this,DriveService::class.java));result.success(journal.fixes()) }
                    "clear" -> { check(!DriveService.running&&!DriveService.starting);journal.discard(call.arguments as String);result.success(null) }
                    else -> result.notImplemented()
                }
            }}catch(e:Exception){result.error("drive",e.message,null)}
        }
    }
}
