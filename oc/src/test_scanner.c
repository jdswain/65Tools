// test_scanner.c - Test suite for the Oberon Scanner (ORS)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "Oberon.h"
#include "Texts.h"
#include "ORS.h"

// Test counter
static int tests_run = 0;
static int tests_passed = 0;

// Helper function to create a text from string
static Texts_Text* create_test_text(const char* content) {
    Texts_Text* text = (Texts_Text*)malloc(sizeof(Texts_Text));
    text->len = strlen(content);
    text->maxlen = text->len + 1;
    text->data = (char*)malloc(text->maxlen);
    strcpy(text->data, content);
    return text;
}

// Helper function to free test text
static void free_test_text(Texts_Text* text) {
    if (text) {
        if (text->data) free(text->data);
        free(text);
    }
}

// Test result checking
#define ASSERT_EQ(expected, actual, test_name) \
    do { \
        tests_run++; \
        if ((expected) == (actual)) { \
            tests_passed++; \
            printf("PASS: %s\n", test_name); \
        } else { \
            printf("FAIL: %s - expected %d, got %d\n", test_name, (int)(expected), (int)(actual)); \
        } \
    } while(0)

#define ASSERT_STR_EQ(expected, actual, test_name) \
    do { \
        tests_run++; \
        if (strcmp((expected), (actual)) == 0) { \
            tests_passed++; \
            printf("PASS: %s\n", test_name); \
        } else { \
            printf("FAIL: %s - expected '%s', got '%s'\n", test_name, (expected), (actual)); \
        } \
    } while(0)

// Test functions
void test_keywords(void) {
    printf("\n=== Testing Keywords ===\n");
    
    Texts_Text* text = create_test_text("MODULE IF THEN ELSE END WHILE DO");
    ORS_Init(text, 0);
    
    INTEGER sym;
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_module, sym, "MODULE keyword");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_if, sym, "IF keyword");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_then, sym, "THEN keyword");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_else, sym, "ELSE keyword");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_end, sym, "END keyword");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_while, sym, "WHILE keyword");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_do, sym, "DO keyword");
    
    free_test_text(text);
}

void test_identifiers(void) {
    printf("\n=== Testing Identifiers ===\n");
    
    Texts_Text* text = create_test_text("myVar x123 _test CamelCase");
    ORS_Init(text, 0);
    
    INTEGER sym;
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_ident, sym, "Simple identifier");
    ASSERT_STR_EQ("myVar", ORS_id, "Identifier value: myVar");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_ident, sym, "Alphanumeric identifier");
    ASSERT_STR_EQ("x123", ORS_id, "Identifier value: x123");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_ident, sym, "Underscore identifier");
    ASSERT_STR_EQ("_test", ORS_id, "Identifier value: _test");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_ident, sym, "CamelCase identifier");
    ASSERT_STR_EQ("CamelCase", ORS_id, "Identifier value: CamelCase");
    
    free_test_text(text);
}

void test_numbers(void) {
    printf("\n=== Testing Numbers ===\n");
    
    Texts_Text* text = create_test_text("123 456.789 0 42H 65X");
    ORS_Init(text, 0);
    
    INTEGER sym;
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_int, sym, "Integer literal");
    ASSERT_EQ(123, ORS_ival, "Integer value: 123");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_real, sym, "Real literal");
    // Note: floating point comparison should be more sophisticated in production
    printf("Real value: %f (expected ~456.789)\n", ORS_rval);
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_int, sym, "Zero literal");
    ASSERT_EQ(0, ORS_ival, "Integer value: 0");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_int, sym, "Hexadecimal literal");
    ASSERT_EQ(0x42, ORS_ival, "Hex value: 42H");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_char, sym, "Character literal");
    ASSERT_EQ(65, ORS_ival, "Character value: 65X (A)");
    
    free_test_text(text);
}

void test_strings(void) {
    printf("\n=== Testing Strings ===\n");
    
    Texts_Text* text = create_test_text("\"Hello\" \"World!\" \"\" \"Test string\"");
    ORS_Init(text, 0);
    
    INTEGER sym;
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_string, sym, "String literal");
    ASSERT_STR_EQ("Hello", ORS_str, "String value: Hello");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_string, sym, "String with punctuation");
    ASSERT_STR_EQ("World!", ORS_str, "String value: World!");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_string, sym, "Empty string");
    ASSERT_STR_EQ("", ORS_str, "String value: empty");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_string, sym, "String with spaces");
    ASSERT_STR_EQ("Test string", ORS_str, "String value: Test string");
    
    free_test_text(text);
}

void test_operators(void) {
    printf("\n=== Testing Operators ===\n");
    
    Texts_Text* text = create_test_text("+ - * / := = # < <= > >= ( ) [ ] { }");
    ORS_Init(text, 0);
    
    INTEGER sym;
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_plus, sym, "Plus operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_minus, sym, "Minus operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_times, sym, "Times operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_rdiv, sym, "Division operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_becomes, sym, "Assignment operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_eql, sym, "Equality operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_neq, sym, "Not equal operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_lss, sym, "Less than operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_leq, sym, "Less or equal operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_gtr, sym, "Greater than operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_geq, sym, "Greater or equal operator");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_lparen, sym, "Left parenthesis");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_rparen, sym, "Right parenthesis");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_lbrak, sym, "Left bracket");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_rbrak, sym, "Right bracket");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_lbrace, sym, "Left brace");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_rbrace, sym, "Right brace");
    
    free_test_text(text);
}

void test_comments(void) {
    printf("\n=== Testing Comments ===\n");
    
    Texts_Text* text = create_test_text("before (* comment *) after (* nested (* comment *) *) final");
    ORS_Init(text, 0);
    
    INTEGER sym;
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_ident, sym, "Identifier before comment");
    ASSERT_STR_EQ("before", ORS_id, "Value: before");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_ident, sym, "Identifier after comment");
    ASSERT_STR_EQ("after", ORS_id, "Value: after");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_ident, sym, "Identifier after nested comment");
    ASSERT_STR_EQ("final", ORS_id, "Value: final");
    
    free_test_text(text);
}

void test_whitespace(void) {
    printf("\n=== Testing Whitespace Handling ===\n");
    
    Texts_Text* text = create_test_text("  \t\n  x  \t  123  \n\r  +  ");
    ORS_Init(text, 0);
    
    INTEGER sym;
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_ident, sym, "Identifier with surrounding whitespace");
    ASSERT_STR_EQ("x", ORS_id, "Value: x");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_int, sym, "Number with surrounding whitespace");
    ASSERT_EQ(123, ORS_ival, "Value: 123");
    
    ORS_Get(&sym);
    ASSERT_EQ(ORS_plus, sym, "Operator with surrounding whitespace");
    
    free_test_text(text);
}

void test_complete_program(void) {
    printf("\n=== Testing Complete Program Fragment ===\n");
    
    const char* program = 
        "MODULE Test;\n"
        "VAR x: INTEGER;\n"
        "BEGIN\n"
        "  x := 42;\n"
        "  IF x > 0 THEN\n"
        "    x := x + 1\n"
        "  END\n"
        "END Test.";
    
    Texts_Text* text = create_test_text(program);
    ORS_Init(text, 0);
    
    INTEGER sym;
	/*
    const char* expected_tokens[] = {
        "MODULE", "Test", ";", "VAR", "x", ":", "INTEGER", ";",
        "BEGIN", "x", ":=", "42", ";", "IF", "x", ">", "0", "THEN",
        "x", ":=", "x", "+", "1", "END", "END", "Test", "."
    };
    */
    printf("Scanning complete program...\n");
    int token_count = 0;
    
    do {
        ORS_Get(&sym);
        if (sym != ORS_eof) {
            if (sym == ORS_ident) {
                printf("Token %d: IDENT(%s)\n", token_count, ORS_id);
            } else if (sym == ORS_int) {
                printf("Token %d: INT(%d)\n", token_count, ORS_ival);
            } else {
                printf("Token %d: SYMBOL(%d)\n", token_count, sym);
            }
            token_count++;
        }
    } while (sym != ORS_eof);
    
    printf("Total tokens scanned: %d\n", token_count);
    tests_run++;
    if (token_count > 20) {  // Should be around 27 tokens
        tests_passed++;
        printf("PASS: Complete program scanning\n");
    } else {
        printf("FAIL: Complete program scanning - too few tokens\n");
    }
    
    free_test_text(text);
}

void test_error_handling(void) {
    printf("\n=== Testing Error Handling ===\n");
    
    Texts_Text* text = create_test_text("\"unterminated string 123abc @ $");
    ORS_Init(text, 0);
    
    INTEGER sym;
    int initial_errors = ORS_errcnt;
    
    // This should generate some errors
    while (ORS_errcnt < 5) {  // Limit to avoid infinite loop
        ORS_Get(&sym);
        if (sym == ORS_eof) break;
    }
    
    tests_run++;
    if (ORS_errcnt > initial_errors) {
        tests_passed++;
        printf("PASS: Error handling - %d errors detected\n", ORS_errcnt);
    } else {
        printf("FAIL: Error handling - no errors detected\n");
    }
    
    free_test_text(text);
}

int main(void) {
    printf("Oberon Scanner Test Suite\n");
    printf("=========================\n");
    
    // Run all tests
    test_keywords();
    test_identifiers();
    test_numbers();
    test_strings();
    test_operators();
    test_comments();
    test_whitespace();
    test_complete_program();
    test_error_handling();
    
    // Print summary
    printf("\n=== Test Summary ===\n");
    printf("Tests run: %d\n", tests_run);
    printf("Tests passed: %d\n", tests_passed);
    printf("Tests failed: %d\n", tests_run - tests_passed);
    printf("Success rate: %.1f%%\n", (tests_passed * 100.0) / tests_run);
    
    if (tests_passed == tests_run) {
        printf("\n🎉 All tests passed!\n");
        return 0;
    } else {
        printf("\n❌ Some tests failed.\n");
        return 1;
    }
}
