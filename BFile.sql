--changed by user 2
CREATE DIRECTORY CPAS_BINFILE AS 'C:\TEMP';

GRANT READ, WRITE ON DIRECTORY CPAS_BINFILE TO CLIENT_PPL_LDEV;

create table BINFILE2
(
  fileid    NUMBER(12) not null,
  --filename  VARCHAR2(255) not null,
  BINFILE   BFILE,
  processid NUMBER(12)
);

INSERT INTO BINFILE2 (FILEID, BINFILE) VALUES (2, BFILENAME('CPAS_BINFILE', 'cpasWS.log') );
INSERT INTO BINFILE2 (FILEID, BINFILE) VALUES (1, BFILENAME('CPAS_BINFILE', 'MemberStmt.38167..-----.PEN100016259414.20160331.pdf'));


CREATE OR REPLACE PACKAGE CP_BinFile AS

DEFAULT_DIR CONSTANT ALL_DIRECTORIES.DIRECTORY_NAME%TYPE := 'CPAS_BINFILE';

FUNCTION GetDirObjName( oBFile BFILE ) RETURN VARCHAR2;

FUNCTION GetFileName( oBFile BFILE ) RETURN VARCHAR2;

PROCEDURE GetFileName( oBFile BFILE, cpPath OUT VARCHAR2, cpFileName OUT VARCHAR2 );

FUNCTION GetBlobFromBFile( oBFile BFILE ) RETURN BLOB;

PROCEDURE SaveBlobToBFile( oBlob IN OUT NOCOPY BLOB, oBFile IN OUT NOCOPY BFILE );

FUNCTION GetBlobFromRemoteDB( npFileID NUMBER ) RETURN BLOB;

PROCEDURE GetBinFileFromRemoteDB( cpClnt VARCHAR2, cpMKey VARCHAR2, cpPlan VARCHAR2 );

PROCEDURE SaveBlobInRemoteDB( oBlob BLOB, npFileID NUMBER, cpFileName VARCHAR2, npProcessID NUMBER DEFAULT NULL );

PROCEDURE DeleteBlobFromRemoteDB( npFileID NUMBER );

END;
/

CREATE OR REPLACE PACKAGE BODY CP_BinFile AS

scPath ALL_DIRECTORIES.DIRECTORY_PATH%TYPE;
scDirObjName ALL_DIRECTORIES.DIRECTORY_NAME%TYPE;


FUNCTION GetFileName( oBFile BFILE ) RETURN VARCHAR2 AS

	cDirObjName ALL_DIRECTORIES.DIRECTORY_NAME%TYPE;
	cFileName VARCHAR2(200);
	
	BEGIN

		DBMS_LOB.FileGetName( oBFile, cDirObjName, cFileName );

		RETURN cFileName;

	END;

FUNCTION GetDirObjName( oBFile BFILE ) RETURN VARCHAR2 AS

	cDirObjName ALL_DIRECTORIES.DIRECTORY_NAME%TYPE;
	cFileName VARCHAR2(200);
	
	BEGIN

		DBMS_LOB.FileGetName( oBFile, cDirObjName, cFileName );

		RETURN cDirObjName;

	END;

PROCEDURE GetFileName( oBFile BFILE, cpPath OUT VARCHAR2, cpFileName OUT VARCHAR2 ) AS

	cDirObjName ALL_DIRECTORIES.DIRECTORY_NAME%TYPE;

   CURSOR curD( cpDirObjName VARCHAR2 ) IS SELECT DIRECTORY_PATH FROM ALL_DIRECTORIES WHERE DIRECTORY_NAME = cpDirObjName;

	BEGIN

		DBMS_LOB.FileGetName( oBFile, cDirObjName, cpFileName );

		IF scDirObjName IS NULL OR scDirObjName <> cDirObjName THEN
			OPEN curD( cDirObjName );
			FETCH curD INTO cpPath;
			CLOSE curD;
			scPath := cpPath;
			scDirObjName := cDirObjName;
		ELSE
			cpPath := scPath;
		END IF;

	END;

FUNCTION GetBlobFromBFile( oBFile BFILE ) RETURN BLOB AS

   oBlob BLOB;
   oBFile2 BFILE;
   nSize NUMBER;
   
	BEGIN
		
		oBFile2 := oBFile;
		DBMS_LOB.CREATETEMPORARY( oBlob, TRUE, DBMS_LOB.SESSION );
		DBMS_LOB.FILEOPEN( oBFile2, DBMS_LOB.FILE_READONLY );
		nSize := DBMS_LOB.GETLENGTH( oBFile2 );
		DBMS_LOB.LOADFROMFILE( oBlob, oBFile2, nSize );
		DBMS_LOB.FILECLOSE( oBFile2 );
		--DBMS_LOB.FREETEMPORARY( oBlob );

		RETURN oBlob;

	END;


PROCEDURE SaveBlobToBFile( oBlob IN OUT NOCOPY BLOB, oBFile IN OUT NOCOPY BFILE ) AS

   nStart NUMBER;
   nLen NUMBER;
   nCount NUMBER;
   UTL_FILE_BUFFER_SIZE CONSTANT NUMBER := 32767;
   oBuffer RAW(32767);
   fFile UTL_FILE.FILE_TYPE;
   cPath VARCHAR2(200);
   cFileName VARCHAR2(200);
   
	BEGIN

		GetFileName( oBFile, cPath, cFileName );
		
		IF oBlob IS NOT NULL THEN
			nStart := 1;
			nLen := DBMS_LOB.GETLENGTH(oBlob);
			nCount := UTL_FILE_BUFFER_SIZE;
			fFile := utl_file.fopen(cPath, cFileName, 'wb', UTL_FILE_BUFFER_SIZE);

			WHILE nStart<nLen LOOP
				DBMS_LOB.read(oBlob,nCount, nStart, oBuffer);
				UTL_FILE.put_raw(fFile, oBuffer, TRUE);
				UTL_FILE.FFLUSH(fFile);
  				nStart := nStart+nCount;
			END LOOP;

			UTL_FILE.FCLOSE(fFile);
   	END IF;
	EXCEPTION
   	WHEN OTHERS THEN
      	IF UTL_FILE.is_open(fFile) THEN
         	UTL_FILE.fClose(fFile);
         END IF;
         RAISE;
   END;


FUNCTION GetBlobFromRemoteDB( npFileID NUMBER ) RETURN BLOB AS
	PRAGMA AUTONOMOUS_TRANSACTION;
	oBlob BLOB;
	BEGIN

	  DELETE FROM CT$BLOB;
	  INSERT INTO CT$BLOB (FILEITEM) (SELECT FILEITEM FROM BINFILE3 WHERE FILEID = npFileID);
	  SELECT FILEITEM INTO oBlob FROM CT$BLOB;
	  DELETE FROM CT$BLOB;
	  COMMIT;

	  RETURN  oBlob;

	END;

PROCEDURE GetBinFileFromRemoteDB( cpClnt VARCHAR2, cpMKey VARCHAR2, cpPlan VARCHAR2 ) AS
	BEGIN

	  DELETE FROM CT$BINFILE;
	  
	  FOR recMPD IN (SELECT * FROM MEMBER_PLAN_DOCUMENT WHERE CLNT = cpClnt AND MKEY = cpMKey AND NVL(PLAN, '99') = NVL(cpPlan, '99') AND FILEID IS NOT NULL) LOOP
	  
	  		INSERT INTO CT$BINFILE(FILEID, FILENAME, FILEITEM, PROCESSID) (SELECT FILEID, FILENAME, FILEITEM, PROCESSID FROM BINFILE3 WHERE FILEID = recMPD.FILEID);

	  END LOOP;

	END;


PROCEDURE SaveBlobInRemoteDB( oBlob BLOB, npFileID NUMBER, cpFileName VARCHAR2, npProcessID NUMBER DEFAULT NULL ) AS
	BEGIN
	
	   DELETE FROM CT$BLOB;
	   INSERT INTO CT$BLOB (FILEITEM) VALUES ( oBlob );
	   
	   DELETE FROM BINFILE3 WHERE FILEID = npFileID;
	   
	   INSERT INTO BINFILE3 (FILEID, FILENAME, FILEITEM, PROCESSID)
	      (SELECT npFileID, cpFileName, FILEITEM, npProcessID FROM CT$BLOB);
	      
	END;

PROCEDURE DeleteBlobFromRemoteDB( npFileID NUMBER ) AS
	BEGIN

		DELETE FROM BINFILE3 WHERE FILEID = npFileID;
		
	END;


END;
/


CREATE OR REPLACE FORCE VIEW CV$BINFILE2 AS
SELECT FILEID, CP_BinFile.GetDirObjName( BINFILE ) DIRECTORY, CP_BinFile.GetFileName( BINFILE ) FILENAME, CP_BinFile.GetBlobFromBFile( BINFILE ) FILEITEM, PROCESSID
FROM BINFILE2
/

CREATE OR REPLACE TRIGGER CV$BINFILE2$TI$I
INSTEAD OF INSERT ON CV$BINFILE2
FOR EACH ROW
DECLARE
   oBFile BFILE;
   oBlob BLOB;
BEGIN

   oBFile := BFileName( NVL(:NEW.DIRECTORY, CP_BinFile.DEFAULT_DIR), :NEW.FILENAME );
   IF :NEW.FILEITEM IS NOT NULL THEN
      oBlob := :NEW.FILEITEM;
      CP_BinFile.SaveBlobToBFile( oBlob, oBFile );
   END IF;
   INSERT INTO BINFILE2 (FILEID, PROCESSID, BINFILE) VALUES (:NEW.FILEID, :NEW.PROCESSID, oBFile );
      
END;
/


CREATE OR REPLACE TRIGGER CV$BINFILE2$TI$U
INSTEAD OF UPDATE ON CV$BINFILE2
FOR EACH ROW
DECLARE
   oBFile BFILE;
   oBlob BLOB;
BEGIN

   oBFile := BFileName( :NEW.DIRECTORY, :NEW.FILENAME );
   IF :NEW.FILEITEM IS NOT NULL THEN
      oBlob := :NEW.FILEITEM;
      CP_BinFile.SaveBlobToBFile( oBlob, oBFile );
   END IF;
   UPDATE BINFILE2 SET PROCESSID = :NEW.PROCESSID, BINFILE = oBFile WHERE FILEID = :OLD.FILEID;
   
END;
/


DECLARE
   oBFile BFILE;
   oBlob BLOB;
   cFileName VARCHAR2(100) := 'WelcomeLetter.38179.731.FC.PEN100543958321.20150731.pdf';
BEGIN

	oBFile := BFileName( CP_BinFile.DEFAULT_DIR, cFileName );
	oBlob := CP_BinFile.GetBlobFromBFile( oBFile );
	
	INSERT INTO CV$BINFILE2 (FILEID, FILENAME, FILEITEM)  VALUES (3, 'WelcomeLetter.pdf', oBlob);
	
END;
/

DECLARE
   oBFile BFILE;
   oBlob BLOB;
   cFileName VARCHAR2(100) := 'WelcomeLetter.38179.731.FC.PEN100543958321.20150731.pdf';
BEGIN

	oBFile := BFileName( CP_BinFile.DEFAULT_DIR, cFileName );
	oBlob := CP_BinFile.GetBlobFromBFile( oBFile );
	
	UPDATE CV$BINFILE2 SET FILEITEM = oBlob WHERE FILEID = 2;
	
END;
/


----------------------------------------------------------------------------------------------------------------
-- Need to convert BINFILE into a temporary table
-- Transfer data from BINFILE@remoteDB to BINFILE
-- Create I/U/D triggers on BINFILE to update the corresponding table in the remote database

--Need to create a private synonym
create public database link CLIENT_PPL_DEV
  connect to CLIENT_PPL_DEV
  using 'S-ORA-009.PPL';
  
-- Create the synonym 
CREATE OR REPLACE SYNONYM BINFILE3 FOR CLIENT_PPL_DEV.BINFILE@CLIENT_PPL_DEV;

--CREATE OR REPLACE FORCE VIEW CV$BINFILE3 AS SELECT FILEID, CP_BinFile.GetBlobFromRemoteDB( FILEID ) FILEITEM, FILENAME, PROCESSID FROM BINFILE3;

--create global temporary table CT$BLOB (FILEITEM BLOB) ON COMMIT PRESERVE ROWS;

/*
CREATE OR REPLACE TRIGGER CV$BINFILE3$TI$I
INSTEAD OF INSERT ON CV$BINFILE3
FOR EACH ROW
DECLARE
   oBFile BFILE;
   oBlob BLOB;
BEGIN

   CP_BinFile.SaveBlobInRemoteDB( :NEW.FILEITEM, :NEW.FILEID, :NEW.FILENAME, :NEW.PROCESSID );
      
END;



CREATE OR REPLACE TRIGGER CV$BINFILE3$TI$U
INSTEAD OF UPDATE ON CV$BINFILE3
FOR EACH ROW
BEGIN

   CP_BinFile.SaveBlobInRemoteDB( :NEW.FILEITEM, :NEW.FILEID, :NEW.FILENAME, :NEW.PROCESSID );
   
END;



DECLARE
   oBFile BFILE;
   oBlob BLOB;
   cFileName VARCHAR2(100) := 'WelcomeLetter.38179.731.FC.PEN100543958321.20150731.pdf';
BEGIN

	oBFile := BFileName( CP_BinFile.DEFAULT_DIR, cFileName );
	oBlob := CP_BinFile.GetBlobFromBFile( oBFile );
	
	--Did not work!
	--INSERT INTO CV$BINFILE3 (FILEID, FILENAME, FILEITEM)  VALUES (-33, 'WelcomeLetter.pdf', oBlob);
	
	CP_BinFile.SaveBlobInRemoteDB( oBlob, -33, X.PDF, NULL );	
	
END;


DELETE FROM CV$BINFILE3 WHERE FILEID=-33;
*/


CREATE GLOBAL TEMPORARY TABLE CT$BINFILE (
  fileid    NUMBER(12) not null,
  filename  VARCHAR2(255) not null,
  fileitem  BLOB default EMPTY_BLOB(),
  processid NUMBER(12)
) ON COMMIT PRESERVE ROWS;


CREATE OR REPLACE TRIGGER CT$BINFILE3$TA$I
AFTER INSERT ON CT$BINFILE
FOR EACH ROW
BEGIN

   CP_BinFile.SaveBlobInRemoteDB( :NEW.FILEITEM, :NEW.FILEID, :NEW.FILENAME, :NEW.PROCESSID );
      
END;
/

CREATE OR REPLACE TRIGGER CT$BINFILE3$TA$D
AFTER DELETE ON CT$BINFILE
FOR EACH ROW
BEGIN

   CP_BinFile.DeleteBolobFromRemoteDB( :OLD.FILEID );
      
END;
/


DECLARE
   oBFile BFILE;
   oBlob BLOB;
   cFileName VARCHAR2(100) := 'WelcomeLetter.38179.731.FC.PEN100543958321.20150731.pdf';
BEGIN

	oBFile := BFileName( CP_BinFile.DEFAULT_DIR, cFileName );
	oBlob := CP_BinFile.GetBlobFromBFile( oBFile );
	
	INSERT INTO CT$BINFILE(FILEID, FILENAME, FILEITEM)  VALUES (-33, 'WelcomeLetter.pdf', oBlob);
	
END;
