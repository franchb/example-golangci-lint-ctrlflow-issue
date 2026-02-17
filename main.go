package main

import (
	"fmt"
	"unicode"

	"github.com/twmb/franz-go/pkg/kgo"
)

func main() {
	// Use unicode — one of the stdlib packages that triggers the panic
	fmt.Println("Is 'A' a letter?", unicode.IsLetter('A'))
	fmt.Println("Is '1' a digit?", unicode.IsDigit('1'))

	// Use franz-go — the kbin transitive dep also triggers the panic
	opts := []kgo.Opt{
		kgo.SeedBrokers("localhost:9092"),
		kgo.ConsumeTopics("test-topic"),
	}

	client, err := kgo.NewClient(opts...)
	if err != nil {
		fmt.Println("Error creating client:", err)
		return
	}
	defer client.Close()

	fmt.Println("Kafka client created successfully")
}
