/* test_orb.c - Test program for the ORB symbol table module */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ORS.h"
#include "ORB.h"

/* Helper function to print object information */
void PrintObject(ObjectPtr obj, int indent) {
    int i;
    
    if (obj == NULL) return;
    
    /* Print indentation */
    for (i = 0; i < indent; i++) printf("  ");
    
    /* Print object info */
    printf("Object: %s", obj->name);
    
    switch (obj->class) {
        case Head:  printf(" [Head]"); break;
        case Const: printf(" [Const] val=%d", obj->val); break;
        case Var:   printf(" [Var]"); break;
        case Par:   printf(" [Par]"); break;
        case Fld:   printf(" [Fld] offset=%d", obj->val); break;
        case Typ:   printf(" [Type]"); break;
        case SProc: printf(" [SProc] code=%d", obj->val); break;
        case SFunc: printf(" [SFunc] code=%d", obj->val); break;
        case Mod:   printf(" [Module]"); break;
    }
    
    if (obj->expo) printf(" (exported)");
    if (obj->rdo) printf(" (read-only)");
    
    /* Print type info if available */
    if (obj->type != NULL) {
        printf(" type=");
        switch (obj->type->form) {
            case Byte:    printf("Byte"); break;
            case Bool:    printf("Bool"); break;
            case Char:    printf("Char"); break;
            case Int:     printf("Int"); break;
            case Real:    printf("Real"); break;
            case Set:     printf("Set"); break;
            case Pointer: printf("Pointer"); break;
            case NilTyp:  printf("Nil"); break;
            case NoTyp:   printf("NoType"); break;
            case Proc:    printf("Proc"); break;
            case String:  printf("String"); break;
            case Array:   printf("Array[%d]", obj->type->len); break;
            case Record:  printf("Record"); break;
        }
    }
    
    printf("\n");
    
    /* Print nested objects (for records, modules, etc.) */
    if (obj->dsc != NULL) {
        PrintObject(obj->dsc, indent + 1);
    }
    
    /* Print next object in list */
    if (obj->next != NULL) {
        PrintObject(obj->next, indent);
    }
}

/* Test basic symbol table operations */
void TestBasicOperations() {
    ObjectPtr obj;
    
    printf("\n=== Testing Basic Symbol Table Operations ===\n");
    
    /* Initialize the symbol table */
    ORB_Initialize();
    ORB_Init();
    
    /* Test NewObj */
    printf("\n1. Creating new objects:\n");
    
    strcpy(ORS_id, "myVar");
    NewObj(&obj, ORS_id, Var);
    obj->type = intType;
    obj->expo = true;
    printf("   Created: %s\n", obj->name);
    
    strcpy(ORS_id, "myConst");
    NewObj(&obj, ORS_id, Const);
    obj->type = intType;
    obj->val = 42;
    printf("   Created: %s = %d\n", obj->name, obj->val);
    
    /* Test duplicate detection */
    strcpy(ORS_id, "myVar");
    NewObj(&obj, ORS_id, Var);
    printf("   Tried to create duplicate 'myVar' - should show error above\n");
    
    /* Test thisObj */
    printf("\n2. Finding objects:\n");
    strcpy(ORS_id, "myVar");
    obj = thisObj();
    if (obj != NULL) {
        printf("   Found: %s\n", obj->name);
    } else {
        printf("   Not found: %s\n", ORS_id);
    }
    
    strcpy(ORS_id, "nonExistent");
    obj = thisObj();
    if (obj != NULL) {
        printf("   Found: %s\n", obj->name);
    } else {
        printf("   Not found: %s\n", ORS_id);
    }
}

/* Test scope operations */
void TestScopes() {
    ObjectPtr obj;
    
    printf("\n=== Testing Scope Operations ===\n");
    
    /* Create objects in outer scope */
    strcpy(ORS_id, "outerVar");
    NewObj(&obj, ORS_id, Var);
    obj->type = intType;
    printf("Created in outer scope: %s\n", obj->name);
    
    /* Open new scope */
    OpenScope();
    printf("Opened new scope\n");
    
    /* Create objects in inner scope */
    strcpy(ORS_id, "innerVar");
    NewObj(&obj, ORS_id, Var);
    obj->type = intType;
    printf("Created in inner scope: %s\n", obj->name);
    
    /* Shadow outer variable */
    strcpy(ORS_id, "outerVar");
    NewObj(&obj, ORS_id, Var);
    obj->type = realType;
    printf("Created shadow in inner scope: %s\n", obj->name);
    
    /* Test finding objects */
    printf("\nFinding objects in inner scope:\n");
    strcpy(ORS_id, "innerVar");
    obj = thisObj();
    printf("   %s: %s\n", ORS_id, obj != NULL ? "found" : "not found");
    
    strcpy(ORS_id, "outerVar");
    obj = thisObj();
    printf("   %s: %s (should find inner version)\n", ORS_id, obj != NULL ? "found" : "not found");
    
    /* Close scope */
    CloseScope();
    printf("\nClosed scope\n");
    
    /* Test finding objects after closing scope */
    printf("Finding objects after closing scope:\n");
    strcpy(ORS_id, "innerVar");
    obj = thisObj();
    printf("   %s: %s\n", ORS_id, obj != NULL ? "found" : "not found");
    
    strcpy(ORS_id, "outerVar");
    obj = thisObj();
    printf("   %s: %s (should find outer version)\n", ORS_id, obj != NULL ? "found" : "not found");
}

/* Test type operations */
void TestTypes() {
    ObjectPtr obj, fld;
    TypePtr recType, arrType, ptrType;
    
    printf("\n=== Testing Type Operations ===\n");
    
    /* Create a record type */
    recType = (TypePtr)calloc(1, sizeof(ORB_Type));
    recType->form = Record;
    recType->size = 8;
    recType->dsc = NULL;
    
    /* Add fields to record */
    fld = (ObjectPtr)calloc(1, sizeof(ORB_Object));
    strcpy(fld->name, "x");
    fld->class = Fld;
    fld->type = intType;
    fld->val = 0;  /* offset */
    fld->next = recType->dsc;
    recType->dsc = fld;
    
    fld = (ObjectPtr)calloc(1, sizeof(ORB_Object));
    strcpy(fld->name, "y");
    fld->class = Fld;
    fld->type = intType;
    fld->val = 4;  /* offset */
    fld->next = recType->dsc;
    recType->dsc = fld;
    
    /* Create type object */
    strcpy(ORS_id, "Point");
    NewObj(&obj, ORS_id, Typ);
    obj->type = recType;
    recType->typobj = obj;
    printf("Created record type: %s\n", obj->name);
    
    /* Test thisfield */
    printf("Testing field lookup:\n");
    strcpy(ORS_id, "x");
    fld = thisfield(recType);
    printf("   Field %s: %s\n", ORS_id, fld != NULL ? "found" : "not found");
    
    strcpy(ORS_id, "z");
    fld = thisfield(recType);
    printf("   Field %s: %s\n", ORS_id, fld != NULL ? "found" : "not found");
    
    /* Create array type */
    arrType = (TypePtr)calloc(1, sizeof(ORB_Type));
    arrType->form = Array;
    arrType->base = intType;
    arrType->len = 10;
    arrType->size = 40;  /* 10 * 4 */
    
    strcpy(ORS_id, "IntArray");
    NewObj(&obj, ORS_id, Typ);
    obj->type = arrType;
    printf("\nCreated array type: %s[10]\n", obj->name);
    
    /* Create pointer type */
    ptrType = (TypePtr)calloc(1, sizeof(ORB_Type));
    ptrType->form = Pointer;
    ptrType->base = recType;
    ptrType->size = 4;
    
    strcpy(ORS_id, "PointPtr");
    NewObj(&obj, ORS_id, Typ);
    obj->type = ptrType;
    printf("Created pointer type: %s -> Point\n", obj->name);
}

/* Display the universe (built-in identifiers) */
void DisplayUniverse() {
    printf("\n=== Universe (Built-in Identifiers) ===\n");
    
    if (universe != NULL && universe->next != NULL) {
        PrintObject(universe->next, 0);
    }
}

/* Display the SYSTEM module */
void DisplaySystem() {
    printf("\n=== SYSTEM Module ===\n");
    
    if (systemScope != NULL) {
        PrintObject(systemScope, 0);
    }
}

int main() {
    /* Initialize ORS for identifier handling */
  //ORS_Init();
    
    /* Initialize ORB */
    ORB_Initialize();
    
    /* Run tests */
    TestBasicOperations();
    TestScopes();
    TestTypes();
    DisplayUniverse();
    DisplaySystem();
    
    printf("\n=== All tests completed ===\n");
    
    return 0;
}
