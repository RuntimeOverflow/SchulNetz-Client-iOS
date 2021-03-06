#import "User.h"
#import "Data.h"

@implementation User
@synthesize me;

@synthesize lessonTypeDict;
@synthesize roomDict;

@synthesize balanceConfirmed;

@synthesize teachers;
@synthesize students;
@synthesize subjects;
@synthesize transactions;
@synthesize absences;
@synthesize lessons;
@synthesize subjectGroups;

-(instancetype)init{
    lessonTypeDict = [[NSMutableDictionary alloc] init];
    roomDict = [[NSMutableDictionary alloc] init];
    
    teachers = [[NSMutableArray alloc] init];
    students = [[NSMutableArray alloc] init];
    subjects = [[NSMutableArray alloc] init];
    transactions = [[NSMutableArray alloc] init];
    absences = [[NSMutableArray alloc] init];
    lessons = [[NSMutableArray alloc] init];
    subjectGroups = [[NSMutableArray alloc] init];
    
    return self;
}

+(User*)load{
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSMutableSet* classes = [[NSMutableSet alloc] init];
    [classes addObject: [NSString class]];
    [classes addObject: [NSMutableArray class]];
    [classes addObject: [NSMutableDictionary class]];
    [classes addObject: [NSDate class]];
    [classes addObject: [UIColor class]];
    [classes addObject: [User class]];
    [classes addObject: [Teacher class]];
    [classes addObject: [Student class]];
    [classes addObject: [Lesson class]];
    [classes addObject: [Subject class]];
    [classes addObject: [Grade class]];
    [classes addObject: [Absence class]];
    [classes addObject: [Transaction class]];
    [classes addObject: [SubjectGroup class]];
    
    User* user = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:[[NSUserDefaults standardUserDefaults] objectForKey:@"user"] error:nil];
    [user processConnections];
    
    if(!user.teachers) user.teachers = [[NSMutableArray alloc] init];
    if(!user.students) user.students = [[NSMutableArray alloc] init];
    if(!user.subjects) user.subjects = [[NSMutableArray alloc] init];
    if(!user.transactions) user.transactions = [[NSMutableArray alloc] init];
    if(!user.absences) user.absences = [[NSMutableArray alloc] init];
    if(!user.lessons) user.lessons = [[NSMutableArray alloc] init];
    if(!user.subjectGroups) user.subjectGroups = [[NSMutableArray alloc] init];
    
    return user;
}

-(void)save{
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:true error:nil] forKey:@"user"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(User*)copy{
    NSMutableSet* classes = [[NSMutableSet alloc] init];
    [classes addObject: [NSString class]];
    [classes addObject: [NSMutableArray class]];
    [classes addObject: [NSMutableDictionary class]];
    [classes addObject: [NSDate class]];
    [classes addObject: [UIColor class]];
    [classes addObject: [User class]];
    [classes addObject: [Teacher class]];
    [classes addObject: [Student class]];
    [classes addObject: [Lesson class]];
    [classes addObject: [Subject class]];
    [classes addObject: [Grade class]];
    [classes addObject: [Absence class]];
    [classes addObject: [Transaction class]];
    [classes addObject: [SubjectGroup class]];
    
    User* copy = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:[NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:true error:nil] error:nil];
    [copy processConnections];
    return copy;
}

-(void)processConnections{
    @try{
        for(Teacher* t in teachers) t.subjects = [[NSMutableArray alloc] init];
        
        for(Subject* s in subjects){
            s.group = NULL;
            
            if(s.identifier != NULL && [s.identifier componentsSeparatedByString:@"-"].count >= 3){
                Teacher* t = [self teacherForShortName:[s.identifier componentsSeparatedByString:@"-"][2]];
                
                if(t != NULL){
                    [t.subjects addObject:s];
                    s.teacher = t;
                }
            }
            
            for(Grade* g in s.grades){
                g.subject = s;
            }
        }
        
        for(Student* s in students){
            if(s.me) {
                me = s;
                break;
            }
        }
        
        for(Absence* a in absences){
            a.subjects = [[NSMutableArray alloc] init];
            
            for(NSString* subjectIdentifier in a.subjectIdentifiers){
                if(subjectIdentifier == NULL) continue;
                
                Subject* s = [self subjectForShortName:[subjectIdentifier componentsSeparatedByString:@"-"][0]];
                
                if(s != NULL) [a.subjects addObject:s];
            }
        }
        
        for(Lesson* l in lessons){
            if(l.lessonIdentifier != NULL && [l.lessonIdentifier componentsSeparatedByString:@"-"].count >= 3){
                Subject* s = [self subjectForShortName:[l.lessonIdentifier componentsSeparatedByString:@"-"][0]];
                if(s != NULL){
                    //[s.lessons addObject:l];
                    l.subject = s;
                }
                
                Teacher* t = [self teacherForShortName:[l.lessonIdentifier componentsSeparatedByString:@"-"][2]];
                if(t != NULL){
                    //[t.lessons addObject:l];
                    l.teacher = t;
                }
            }
            
            if(roomDict[[NSString stringWithFormat:@"%d", l.roomNumber]] != NULL) l.room = roomDict[[NSString stringWithFormat:@"%d", l.roomNumber]];
        }
        
        for(SubjectGroup* g in subjectGroups){
            [g.subjects removeAllObjects];
            
            for(NSString* identifier in g.subjectIdentifiers){
                Subject* s = [self subjectForIdentifier:identifier];
                
                if(s){
                    [g.subjects addObject:s];
                    s.group = g;
                }
            }
        }
    } @catch(NSException *exception){}
    @finally{}
}

-(Teacher*)teacherForShortName:(NSString*)shortName{
    for(Teacher* t in teachers) if([t.shortName.lowercaseString isEqualToString:shortName.lowercaseString]) return t;
    
    return NULL;
}

-(Subject*)subjectForShortName:(NSString*)shortName{
    for(Subject* s in subjects) if([s.shortName.lowercaseString isEqualToString:shortName.lowercaseString]) return s;
    
    return NULL;
}

-(Subject*)subjectForIdentifier:(NSString*)identifier{
    for(Subject *s in subjects) if([s.identifier.lowercaseString isEqualToString:identifier.lowercaseString]) return s;
    
    return NULL;
}

-(void)processLessons:(NSMutableArray*)lessons{
    for(Lesson* l in lessons){
        if(l.lessonIdentifier != NULL && [l.lessonIdentifier componentsSeparatedByString:@"-"].count >= 3){
            Subject* s = [self subjectForShortName:[l.lessonIdentifier componentsSeparatedByString:@"-"][0]];
            if(s != NULL){
                l.subject = s;
            }
            
            Teacher* t = [self teacherForShortName:[l.lessonIdentifier componentsSeparatedByString:@"-"][2]];
            if(t != NULL){
                l.teacher = t;
            }
        }
        
        
        if(roomDict[[NSString stringWithFormat:@"%d", l.roomNumber]] != NULL) l.room = roomDict[[NSString stringWithFormat:@"%d", l.roomNumber]];
    }
}

-(void)encodeWithCoder:(NSCoder*)coder{
    [coder encodeObject:lessonTypeDict forKey:@"lessonTypeDict"];
    [coder encodeObject:roomDict forKey:@"roomDict"];
    
    [coder encodeBool:balanceConfirmed forKey:@"balanceConfirmed"];
    
    [coder encodeObject:teachers forKey:@"teachers"];
    [coder encodeObject:students forKey:@"students"];
    [coder encodeObject:subjects forKey:@"subjects"];
    [coder encodeObject:transactions forKey:@"transactions"];
    [coder encodeObject:absences forKey:@"absences"];
    [coder encodeObject:lessons forKey:@"lessons"];
    [coder encodeObject:subjectGroups forKey:@"subjectGroups"];
}

-(instancetype)initWithCoder:(NSCoder*)coder{
    lessonTypeDict = [coder decodeObjectForKey:@"lessonTypeDict"];
    roomDict = [coder decodeObjectForKey:@"roomDict"];
    
    balanceConfirmed = [coder decodeBoolForKey:@"balanceConfirmed"];
    
    teachers = [coder decodeObjectForKey:@"teachers"];
    students = [coder decodeObjectForKey:@"students"];
    subjects = [coder decodeObjectForKey:@"subjects"];
    transactions = [coder decodeObjectForKey:@"transactions"];
    absences = [coder decodeObjectForKey:@"absences"];
    lessons = [coder decodeObjectForKey:@"lessons"];
    subjectGroups = [coder decodeObjectForKey:@"subjectGroups"];
    
    return self;
}

+(BOOL)supportsSecureCoding{
    return true;
}
@end
