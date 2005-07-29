/* ************************************************************************ */
/*																			*/
/*	Neko VM source															*/
/*  (c)2005 Nicolas Cannasse												*/
/*																			*/
/* ************************************************************************ */
#include <string.h>
#include <stdio.h>
#include "neko.h"
#include "objtable.h"
#include "vmcontext.h"

#define C(x,y)	((x << 8) | y)

static field id_compare;
static field id_string;
field id_loader;
field id_exports;
field id_add;
field id_preadd;
field id_data;
field id_mod;

void neko_init_fields() {
	id_compare = val_id("__compare");
	id_string = val_id("__string");
	id_add = val_id("__add");
	id_preadd = val_id("__preadd");
	id_loader = val_id("loader");
	id_exports = val_id("exports");
	id_data = val_id("__data");
	id_mod = val_id("@m");
}

INLINE int icmp( int a, int b ) {
	return (a == b)?0:((a < b)?-1:1);
}

INLINE int fcmp( tfloat a, tfloat b ) {
	return (a == b)?0:((a < b)?-1:1);
}

INLINE int scmp( const char *s1, int l1, const char *s2, int l2 ) {
	int r = memcmp(s1,s2,(l1 < l2)?l1:l2); 
	return r?r:icmp(l1,l2);
}

EXTERN int val_compare( value a, value b ) {
	char tmp_buf[32];
	switch( C(val_type(a),val_type(b)) ) {
	case C(VAL_INT,VAL_INT):
		return icmp(val_int(a),val_int(b));
	case C(VAL_INT,VAL_FLOAT):
		return fcmp(val_int(a),val_float(b));
	case C(VAL_INT,VAL_STRING): 
		return scmp(tmp_buf,sprintf(tmp_buf,"%d",val_int(a)),val_string(b),val_strlen(b));
	case C(VAL_FLOAT,VAL_INT):
		return fcmp(val_float(a),val_int(b));
	case C(VAL_FLOAT,VAL_FLOAT):
		return fcmp(val_float(a),val_float(b));
	case C(VAL_FLOAT,VAL_STRING):
		return scmp(tmp_buf,sprintf(tmp_buf,"%.10g",val_float(a)),val_string(b),val_strlen(b));
	case C(VAL_STRING,VAL_INT):
		return scmp(val_string(a),val_strlen(a),tmp_buf,sprintf(tmp_buf,"%d",val_int(b)));
	case C(VAL_STRING,VAL_FLOAT):
		return scmp(val_string(a),val_strlen(a),tmp_buf,sprintf(tmp_buf,"%.10g",val_float(b)));
	case C(VAL_STRING,VAL_BOOL):
		return scmp(val_string(a),val_strlen(a),val_bool(b)?"true":"false",val_bool(b)?4:5);
	case C(VAL_BOOL,VAL_STRING):
		return scmp(val_bool(a)?"true":"false",val_bool(a)?4:5,val_string(b),val_strlen(b));
	case C(VAL_STRING,VAL_STRING):
		return scmp(val_string(a),val_strlen(a),val_string(b),val_strlen(b));
	case C(VAL_OBJECT,VAL_OBJECT):
		if( a == b )
			return 0;
		a = val_ocall1(a,id_compare,b);
		if( val_is_int(a) )
			return val_int(a);
		return invalid_comparison;
	default:
		if( a == b )
			return 0;
		return invalid_comparison;
	}
}

typedef struct _stringitem {
	char *str;
	int len;
	struct _stringitem *next;
} * stringitem;

struct _buffer {
	int totlen;
	stringitem data;
};

EXTERN buffer alloc_buffer( const char *init ) {
	buffer b = (buffer)alloc(sizeof(struct _buffer));
	b->totlen = 0;
	b->data = NULL;
	if( init )
		buffer_append(b,init);
	return b;
}

EXTERN void buffer_append_sub( buffer b, const char *s, int len ) {	
	stringitem it;
	if( s == NULL || len <= 0 )
		return;
	b->totlen += len;
	it = (stringitem)alloc(sizeof(struct _stringitem));
	it->str = alloc_private(len+1);
	memcpy(it->str,s,len);
	it->str[len] = 0;
	it->len = len;
	it->next = b->data;
	b->data = it;
}

EXTERN void buffer_append( buffer b, const char *s ) {
	if( s == NULL )
		return;
	buffer_append_sub(b,s,strlen(s));
}

EXTERN value buffer_to_string( buffer b ) {
	value v = alloc_empty_string(b->totlen);
	stringitem it = b->data;
	char *s = (char*)val_string(v) + b->totlen;
	while( it != NULL ) {
		stringitem tmp;
		s -= it->len;
		memcpy(s,it->str,it->len);
		tmp = it->next;
		it = tmp;
	}
	return v;
}

EXTERN void val_buffer( buffer b, value v ) {
	char buf[32];
	int i, l;
	switch( val_type(v) ) {
	case VAL_INT:
		buffer_append_sub(b,buf,sprintf(buf,"%d",val_int(v)));
		break;
	case VAL_STRING:
		buffer_append_sub(b,val_string(v),val_strlen(v));
		break;
	case VAL_FLOAT:
		buffer_append_sub(b,buf,sprintf(buf,"%.10g",val_float(v)));
		break;
	case VAL_NULL:
		buffer_append_sub(b,"null",4);
		break;
	case VAL_BOOL:
		if( val_bool(v) )
			buffer_append_sub(b,"true",4);
		else
			buffer_append_sub(b,"false",5);
		break;
	case VAL_FUNCTION:
		buffer_append_sub(b,buf,sprintf(buf,"#function:%d",val_fun_nargs(v)));
		break;	
	case VAL_OBJECT:
		v = val_ocall0(v,id_string);
		if( val_is_string(v) )
			buffer_append_sub(b,val_string(v),val_strlen(v));
		else
			buffer_append_sub(b,"#object",7);
		break;
	case VAL_ARRAY:
		buffer_append_sub(b,"[",1);
		l = val_array_size(v) - 1;
		for(i=0;i<l;i++) {
			val_buffer(b,val_array_ptr(v)[i]);
			buffer_append_sub(b,",",1);
		}
		if( l >= 0 )
			val_buffer(b,val_array_ptr(v)[l]);
		buffer_append_sub(b,"]",1);
		break;
	case VAL_ABSTRACT:
		buffer_append_sub(b,"#abstract",9);
		break;
	default:
		buffer_append_sub(b,"#unknown",8);
		break;
	}
}

EXTERN field val_id( const char *name ) {
	objtable fields;
	field f;
	value *old;
	value acc = alloc_int(0);
	const char *oname = name;
	while( *name ) {
		acc = alloc_int(223 * val_int(acc) + *((unsigned char*)name));
		name++;
	}
	f = (field)val_int(acc);
	if( NEKO_VM() == NULL )
		return f;	
	fields = NEKO_VM()->fields;
	old = otable_find(fields,f);
	if( old != NULL ) {
		if( scmp(val_string(*old),val_strlen(*old),oname,name - oname) != 0 )
			val_throw(alloc_string("field conflict"));
	} else
		otable_replace(NEKO_VM()->fields,f,copy_string(oname,name - oname));
	return f;
}

EXTERN value val_field( value o, field id ) {
	value *f;
	if( !val_is_object(o) )
		return val_null;
	f = otable_find(((vobject*)o)->table,id);
	if( f == NULL )
		return val_null;
	return *f;
}

EXTERN void iter_fields( value o, void f( value , field, void * ) , void *p ) {
	otable_iter( ((vobject*)o)->table, f, p );
}

EXTERN void val_print( value v ) {
	if( !val_is_string(v) ) {
		buffer b = alloc_buffer(NULL);
		val_buffer(b,v);
		v = buffer_to_string(b);
	}
	NEKO_VM()->print( val_string(v), val_strlen(v) );
}

EXTERN void val_throw( value v ) {
	neko_vm *vm = NEKO_VM();
	vm->this = v;
	longjmp(vm->start,1);
}

/* ************************************************************************ */