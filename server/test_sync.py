import io,json,tempfile,uuid,unittest
from pathlib import Path
import sync

class ExchangeTest(unittest.TestCase):
    def test_offline_queue_retry_second_device_and_conflict(self):
        with tempfile.TemporaryDirectory() as tmp:
            sync.DATA=Path(tmp);(sync.DATA/'pair-key').write_text('test')
            def exchange(cursor,push,key='test'):
                body=json.dumps(dict(cursor=cursor,push=push)).encode()
                status=[]
                result=sync.application({'wsgi.input':io.BytesIO(body),'REQUEST_METHOD':'POST','PATH_INFO':'/api/field-map/sync','HTTP_AUTHORIZATION':'Bearer '+key,'CONTENT_LENGTH':str(len(body))},lambda s,h:status.append(s))
                return status[0],json.loads(b''.join(result))
            uid=lambda:str(uuid.uuid4())
            trail=dict(id=uid(),rev=uid(),parent=None,device=uid(),name='Nadi ridge',created=1,updated=1,parts=[[[-17.8,177.4],[-17.81,177.41]]])
            self.assertTrue(exchange(0,[trail],key='wrong')[0].startswith('401'))
            _,first=exchange(0,[trail]);self.assertEqual(first['changes'],[trail])
            self.assertEqual(exchange(0,[trail])[1],first)
            self.assertEqual(exchange(0,[])[1]['changes'],[trail])
            a=dict(trail,parent=trail['rev'],rev=uid(),name='Hill trail')
            b=dict(a,rev=uid(),device=uid(),name='Ridge trail')
            _,changes=exchange(first['cursor'],[a,b])
            self.assertEqual(changes['changes'],[a,b])
            self.assertTrue(exchange(0,[dict(a,name='overwritten')])[0].startswith('409'))
            self.assertEqual(exchange(changes['cursor'],[])[1]['changes'],[])
            tomb=dict(a,parent=a['rev'],rev=uid(),deleted=True)
            status,res=exchange(changes['cursor'],[tomb])
            self.assertTrue(status.startswith('200'))
            self.assertEqual(res['changes'],[tomb])
            self.assertTrue(exchange(res['cursor'],[dict(tomb,rev=uid(),deleted='yes')])[0].startswith('400'))
if __name__=='__main__':unittest.main()
