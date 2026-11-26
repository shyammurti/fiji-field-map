package net.homelab.offroad

import android.app.*
import android.content.*
import android.database.sqlite.*
import android.location.*
import android.os.*
import android.Manifest
import android.content.pm.PackageManager

/** Separate raw journal survives closing the activity and process death. A sample
 * becomes visible to Flutter only after SQLite has committed it. */
class DriveJournal(ctx: Context) : SQLiteOpenHelper(ctx,"drive-journal.sqlite",null,1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE session(id TEXT PRIMARY KEY, active INTEGER NOT NULL)")
        db.execSQL("CREATE TABLE fixes(seq INTEGER PRIMARY KEY, lat REAL, lon REAL, stamp INTEGER, accuracy REAL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {}
    fun session(): String? = readableDatabase.rawQuery("SELECT id FROM session",null).use { if(it.moveToFirst()) it.getString(0) else null }
    fun start(id: String) { writableDatabase.execSQL("INSERT INTO session VALUES(?,1)", arrayOf(id)) }
    fun stop() { writableDatabase.execSQL("UPDATE session SET active=0") }
    fun discard(id: String) {
        val db=writableDatabase
        db.beginTransaction()
        try {
            if(session()==id){ db.execSQL("DELETE FROM fixes"); db.execSQL("DELETE FROM session") }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    fun count(): Long = readableDatabase.rawQuery("SELECT COUNT(*) FROM fixes",null).use { it.moveToFirst();it.getLong(0) }
    fun fixes(recent: Boolean = false): List<List<Number>> = readableDatabase.rawQuery(if(recent) "SELECT lat,lon,stamp,accuracy FROM (SELECT * FROM fixes ORDER BY seq DESC LIMIT 1000) ORDER BY seq" else "SELECT lat,lon,stamp,accuracy FROM fixes ORDER BY seq",null).use {
        val rows= mutableListOf<List<Number>>()
        while(it.moveToNext()) rows.add(listOf<Number>(it.getDouble(0),it.getDouble(1),it.getLong(2),it.getDouble(3)))
        rows
    }
}

class DriveService : Service(), LocationListener {
    companion object { var running=false; var starting=false }
    private lateinit var journal: DriveJournal
    private lateinit var location: LocationManager
    override fun onCreate() {
        super.onCreate()
        location=getSystemService(LOCATION_SERVICE) as LocationManager
        journal=DriveJournal(this)
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        starting=false
        if(journal.session()==null){stopSelf();return START_NOT_STICKY}
        val channel="trail-recording"
        val manager=getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val builder=if(Build.VERSION.SDK_INT>=26){
            manager.createNotificationChannel(NotificationChannel(channel,"Drive recording",NotificationManager.IMPORTANCE_LOW))
            Notification.Builder(this,channel)
        }else{ @Suppress("DEPRECATION") Notification.Builder(this) }
        val open=PendingIntent.getActivity(this,0,Intent(this,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE)
        try {
            startForeground(31,builder.setSmallIcon(android.R.drawable.ic_menu_mylocation).setContentTitle("Recording drive")
                .setContentText("Open Fiji Field Map to finish and review").setOngoing(true).setContentIntent(open).build())
            if(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED) error("Precise location required")
            location.requestLocationUpdates(LocationManager.GPS_PROVIDER,2000L,3f,this)
            running=true
        } catch(e:Exception){journal.stop();stopSelf()}
        return START_NOT_STICKY
    }
    override fun onLocationChanged(fix:Location) {
        if(!running || !fix.hasAccuracy())return
        try { journal.writableDatabase.execSQL("INSERT INTO fixes(lat,lon,stamp,accuracy) SELECT ?,?,?,? WHERE EXISTS(SELECT 1 FROM session WHERE active=1)", arrayOf<Any>(fix.latitude,fix.longitude,fix.time,fix.accuracy)) }
        catch(e:SQLiteException){running=false;stopSelf()}
    }
    override fun onProviderEnabled(provider:String){}
    override fun onProviderDisabled(provider:String){}
    @Deprecated("Legacy location listener")
    override fun onStatusChanged(provider:String?,status:Int,extras:Bundle?){}
    override fun onDestroy(){
        running=false;starting=false;location.removeUpdates(this)
        try { journal.stop() } finally {journal.close();super.onDestroy()}
    }
}
