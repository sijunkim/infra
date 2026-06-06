-- asset-app 컷오버용 MySQL init 스니펫. **실행하지 말 것** — 컷오버 시 수동 적용.
--
-- 적용 방법(컷오버 단계에서):
--   kubectl -n prodesk exec -it deploy/mysql -- \
--     mysql -uroot -p"$MYSQL_ROOT_PASSWORD" < init-db.sql
--   (또는 NodePort 30306 으로 접속해 실행)
--
-- 기존 MySQL 유저 'kimsijun' 을 재사용한다(asset-app-secret 의 DB_USERNAME/DB_PASSWORD = mysql secret 값).
-- 신규 전용 데이터베이스 `asset` 만 만들고, 그 DB 에 대한 권한을 부여한다.
-- 테이블은 앱 기동 시 schema.sql(CREATE TABLE IF NOT EXISTS)이 생성하므로 여기선 만들지 않는다.

CREATE DATABASE IF NOT EXISTS asset
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- 기존 유저에게 asset DB 권한 부여(유저는 mysql secret 의 MYSQL_USER 와 동일).
GRANT ALL PRIVILEGES ON asset.* TO 'kimsijun'@'%';

FLUSH PRIVILEGES;

-- 검증:
--   SHOW DATABASES LIKE 'asset';
--   SHOW GRANTS FOR 'kimsijun'@'%';
