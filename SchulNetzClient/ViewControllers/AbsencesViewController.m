#import "AbsencesViewController.h"
#import "../Variables.h"
#import "../Data/Absence.h"
#import "../Util.h"

@interface AbsenceCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UILabel *label;
@property (weak, nonatomic) IBOutlet UILabel *additionalLabel;
@end

@implementation AbsenceCell
@end

@interface AbsencesViewController ()
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UIView *headerBackground;

@end

@implementation AbsencesViewController
NSMutableArray<NSNumber*>* primaryExpanded;
NSMutableArray<NSNumber*>* secondaryExpanded;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    primaryExpanded = [[NSMutableArray alloc] init];
    secondaryExpanded = [[NSMutableArray alloc] init];
    
    int totalLessons = 0;
    for(int i = 0; i < [Variables get].user.absences.count; i++){
        primaryExpanded[i] = [NSNumber numberWithBool:false];
        secondaryExpanded[i] = [NSNumber numberWithBool:false];
        
        totalLessons += [Variables get].user.absences[i].lessonCount;
    }
    
    _titleLabel.text = [NSString stringWithFormat:@"Lessons missed: %d", totalLessons];
    _headerBackground.backgroundColor = [Util getTintColor];
    
    _tableView.delegate = self;
    _tableView.dataSource = self;
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    AbsenceCell* cell = [tableView dequeueReusableCellWithIdentifier:@"absenceCell"];
    
    if(indexPath.row == 0){
        cell.label.text = [Variables get].user.absences[indexPath.section].reason.length > 0 ? [Variables get].user.absences[indexPath.section].reason : @"[No description provided]";
        cell.label.textColor = [UIColor blackColor];
        
        cell.additionalLabel.text = [NSString stringWithFormat:@"%d %@", [Variables get].user.absences[indexPath.section].lessonCount, ([Variables get].user.absences[indexPath.section].lessonCount != 1 ? @"Lessons" : @"Lesson")];
        cell.additionalLabel.textColor = [Variables get].user.absences[indexPath.section].excused ? [UIColor blackColor] : [UIColor redColor];
    } else if(indexPath.row == 1 && [Variables get].user.absences[indexPath.section].startDate){
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"dd. MMMM yyyy";
        
        cell.label.text = [NSString stringWithFormat:@"%@%@", [formatter stringFromDate:[Variables get].user.absences[indexPath.section].startDate], ([[Variables get].user.absences[indexPath.section].startDate compare:[Variables get].user.absences[indexPath.section].endDate] != 0 ? [NSString stringWithFormat:@" - %@", [formatter stringFromDate:[Variables get].user.absences[indexPath.section].endDate]] : @"")];
        cell.label.textColor = [UIColor systemGrayColor];
        
        cell.additionalLabel.text = @"";
    } else if(indexPath.row == ([Variables get].user.absences[indexPath.section].startDate ? 2 : 1)){
        cell.label.text = !secondaryExpanded[indexPath.section].boolValue ? @"Show reported lessons" : @"Hide reported lessons";
        cell.label.textColor = [UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:255/255.0];
        
        cell.additionalLabel.text = @"";
    } else{
        int index = (int)indexPath.row - ([Variables get].user.absences[indexPath.section].startDate ? 3 : 2);
        
        if([Variables get].user.absences[indexPath.section].subjects.count > index && [Variables get].user.absences[indexPath.section].subjects[index]){
            cell.label.text = [NSString stringWithFormat:@"%d. %@", index + 1, ([Variables get].user.absences[indexPath.section].subjects[index].name ? [Variables get].user.absences[indexPath.section].subjects[index].name : [Variables get].user.absences[indexPath.section].subjects[index].shortName)];
            cell.label.textColor = [UIColor systemGrayColor];
        }
        
        cell.additionalLabel.text = @"";
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    if(indexPath.row == 0){
        primaryExpanded[indexPath.section] = [NSNumber numberWithBool:!primaryExpanded[indexPath.section].boolValue];
        secondaryExpanded[indexPath.section] = [NSNumber numberWithBool:false];
    } else if(indexPath.row == ([Variables get].user.absences[indexPath.section].startDate ? 2 : 1)){
        secondaryExpanded[indexPath.section] = [NSNumber numberWithBool:!secondaryExpanded[indexPath.section].boolValue];
    }
    
    [tableView reloadData];
}

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    int count = 1;
    
    if(primaryExpanded[section].boolValue){
        if([Variables get].user.absences[section].startDate) count++;
        count++;
        
        if(secondaryExpanded[section].boolValue){
            count += [Variables get].user.absences[section].subjects.count;
        }
    }
    
    return count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return [Variables get].user.absences.count;
}
@end
