package main

import (
	"fmt"
	"runtime"
	"runtime/debug"
)

// In thông tin bộ nhớ
func printMemStats() {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	fmt.Printf("Alloc = %v MiB", m.Alloc/1024/1024)
	fmt.Printf("\tTotalAlloc = %v MiB", m.TotalAlloc/1024/1024)
	fmt.Printf("\tSys = %v MiB", m.Sys/1024/1024)
	fmt.Printf("\tNumGC = %v\n", m.NumGC)
}

func main() {
	// Cài đặt GC
	debug.SetGCPercent(100)

	// Trước khi xử lý
	fmt.Println("--- Bộ nhớ trước khi xử lý ---")
	printMemStats()

	// Gọi hàm debug
	DebugMain()

	// Sau khi xử lý
	fmt.Println("--- Bộ nhớ sau khi xử lý ---")
	printMemStats()
}
