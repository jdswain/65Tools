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
        case ORB_Head:  printf(" [Head]"); break;
        case ORB_Const: printf(" [Const] val=%d", obj->val); break;
        case ORB_Var:   printf(" [Var]"); break;
        case ORB_Par:   printf(" [Par]"); break;
        case ORB_Fld:   printf(" [Fld] offset=%d", obj->val); break;
        case ORB_Typ:   printf(" [Type]"); break;
        case ORB_SProc: printf(" [SProc] code=%d", obj->val); break;
        case ORB_SFunc: printf(" [SFunc] code=%d", obj->val); break;
        case ORB_Mod:   printf(" [Module]"); break;
    }
    
    if (obj->expo) printf(" (exported)");
    if (obj->rdo) printf(" (read-only)");
    
    /* Print type info if available */
    if (obj->type != NULL) {
        printf(" type=");
        switch (obj->type->form) {
            case ORB_Byte:    printf("Byte"); break;
            case ORB_Bool:    printf("Bool"); break;
            case ORB_Char:    printf("Char"); break;
            case ORB_Int:     printf("Int"); break;
            case ORB_Real:    printf("Real"); break;
            case ORB_Set:     printf("Set"); break;
            case ORB_Pointer: printf("Pointer"); break;
            case ORB_NilTyp:  printf("Nil"); break;
            case ORB_NoTyp:   printf("NoType"); break;
            case ORB_Proc:    printf("Proc"); break;
            case ORB_String:  printf("String"); break;
            case ORB_Array:   printf("Array[%d]", obj->type->len); break;
            case ORB_Record:  printf("Record"); break;
        }
        printf(" size=%d", obj->type->size);
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
    NewObj(&obj, ORS_id, ORB_Var);
    obj->type = intType;
    obj->expo = true;
    printf("   Created: %s\n", obj->name);
    
    strcpy(ORS_id, "myConst");
    NewObj(&obj, ORS_id, ORB_Const);
    obj->type = intType;
    obj->val = 42;
    printf("   Created: %s = %d\n", obj->name, obj->val);
    
    /* Test duplicate detection */
    strcpy(ORS_id, "myVar");
    NewObj(&obj, ORS_id, ORB_Var);
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
    NewObj(&obj, ORS_id, ORB_Var);
    obj->type = intType;
    printf("Created in outer scope: %s\n", obj->name);
    
    /* Open new scope */
    OpenScope();
    printf("Opened new scope\n");
    
    /* Create objects in inner scope */
    strcpy(ORS_id, "innerVar");
    NewObj(&obj, ORS_id, ORB_Var);
    obj->type = intType;
    printf("Created in inner scope: %s\n", obj->name);
    
    /* Shadow outer variable */
    strcpy(ORS_id, "outerVar");
    NewObj(&obj, ORS_id, ORB_Var);
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
    recType->form = ORB_Record;
    recType->size = 8;
    recType->dsc = NULL;
    
    /* Add fields to record */
    fld = (ObjectPtr)calloc(1, sizeof(ORB_Object));
    strcpy(fld->name, "x");
    fld->class = ORB_Fld;
    fld->type = intType;
    fld->val = 0;  /* offset */
    fld->next = recType->dsc;
    recType->dsc = fld;
    
    fld = (ObjectPtr)calloc(1, sizeof(ORB_Object));
    strcpy(fld->name, "y");
    fld->class = ORB_Fld;
    fld->type = intType;
    fld->val = 4;  /* offset */
    fld->next = recType->dsc;
    recType->dsc = fld;
    
    /* Create type object */
    strcpy(ORS_id, "Point");
    NewObj(&obj, ORS_id, ORB_Typ);
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
    arrType->form = ORB_Array;
    arrType->base = intType;
    arrType->len = 10;
    arrType->size = 40;  /* 10 * 4 */
    
    strcpy(ORS_id, "IntArray");
    NewObj(&obj, ORS_id, ORB_Typ);
    obj->type = arrType;
    printf("\nCreated array type: %s[10]\n", obj->name);
    
    /* Create pointer type */
    ptrType = (TypePtr)calloc(1, sizeof(ORB_Type));
    ptrType->form = ORB_Pointer;
    ptrType->base = recType;
    ptrType->size = 4;
    
    strcpy(ORS_id, "PointPtr");
    NewObj(&obj, ORS_id, ORB_Typ);
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
