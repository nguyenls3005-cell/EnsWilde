//
//  WQLaunchServices.h
//  WQ Files
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Human app name for a bundle id, from LaunchServices' database (read from
// lsd's container), a built-in table of Apple services, or the parent app.
NSString *_Nullable wq_display_name(NSString *_Nullable bundleID);

// Bundle id of an app or extension data container (/private/var/mobile/
// Containers/Data/...) or an app bundle container, from the same
// LaunchServices database. For iOS 27.2, where the containers' identifier
// attribute can't be read. Nil if unknown.
NSString *_Nullable wq_bundle_id_for_container(NSString *path);

// Whether the name database is loaded; loading it (blocking, off the main
// thread) the first time can take a while, so screens show a status for it.
BOOL wq_display_names_loaded(void);
void wq_load_display_names(void);
// After a user's refresh: search for a database that wasn't found before
// right away instead of waiting a day.
void wq_display_names_reset_miss(void);
// Every app and extension data container the LaunchServices database lists,
// read from storeHint (remembered when it parses) or the remembered location.
// Never scans. Nil when there's no usable database.
NSArray<NSString *> *_Nullable wq_ls_container_paths(NSString *_Nullable storeHint);
// The .app bundle of an installed app, from the same database (for icons
// where iOS won't hand them out). Nil if unknown.
NSString *_Nullable wq_bundle_path_for_id(NSString *bundleID);
// The app bundle containers (/private/var/containers/Bundle/Application/
// <UUID>) of installed apps, from the same database; empty if unknown.
// wq_bundle_id_for_container also labels these.
NSArray<NSString *> *wq_ls_bundle_containers(void);

// App Group folder -> group id (issue #59). The database keeps each app's
// group containers as an embedded binary plist ({group id: folder path},
// sometimes inside a persona dictionary). Only folders that every record
// names with the same single id are mapped. Keys are canonical
// /private/var/mobile/Containers/Shared/AppGroup/<UUID> paths.
NSDictionary<NSString *, NSString *> *wq_ls_group_ids_from_store(NSData *data);
// The group id the current database gives `path`, or nil.
NSString *_Nullable wq_group_id_for_container(NSString *path);

NS_ASSUME_NONNULL_END
