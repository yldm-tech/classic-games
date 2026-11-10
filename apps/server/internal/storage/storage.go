// Package storage 提供 GORM 数据库连接。
// SQLite (pure Go through wasm2go, no CGO and no external database) is the only driver linked today, so the DSN is a SQLite file path. PostgreSQL is the production target and is not wired in yet; the per-domain GormRepo types are written against GORM so that adding the driver here is the only change it needs (docs/08-deployment.md, ADR-011).
package storage

import (
	"time"

	"github.com/ncruces/go-sqlite3/gormlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Open 打开数据库。dsn 为空用内存 SQLite(":memory:")。
func Open(dsn string) (*gorm.DB, error) {
	if dsn == "" {
		dsn = ":memory:"
	}
	db, err := gorm.Open(gormlite.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
		// SQLite has no native timestamp type: GORM hands the driver an RFC 3339 string carrying the writer's UTC
		// offset, and every `ORDER BY created_at` then compares those strings lexicographically. A row stamped
		// "2026-08-26T00:47:58Z" therefore sorts *below* an older row stamped "2026-08-26T09:47:58+09:00", because the
		// comparison reads digits rather than instants. Domain code already writes time.Now().UTC() explicitly, so
		// pinning GORM's auto-timestamps to UTC as well keeps a single representation in every column and makes
		// lexicographic order agree with chronological order.
		NowFunc: func() time.Time { return time.Now().UTC() },
	})
	if err != nil {
		return nil, err
	}
	// SQLite 单写者:连接池限 1 条,把所有访问串行化。
	// 这能杜绝并发写事务相互抢锁导致的 "database is locked"(SQLITE_BUSY);
	// 对 ":memory:" 还能避免多连接各开一个独立空库的隐患。换 PostgreSQL 时去掉此限制。
	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}
	sqlDB.SetMaxOpenConns(1)
	return db, nil
}
