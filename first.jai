OUTPUT_NAME :: "guitar";
OUTPUT_PATH :: "build";
OUTPUT_DATA_PATH :: "build/data";

build :: () {
    options := get_build_options();

    // output stuff
    make_directory_if_it_does_not_exist(OUTPUT_PATH);
    options.output_path = OUTPUT_PATH;
    options.output_executable_name = OUTPUT_NAME;

    make_directory_if_it_does_not_exist(OUTPUT_DATA_PATH);
    copy_file("data/OpenSans-BoldItalic.ttf", "build/data/OpenSans-BoldItalic.ttf");
    copy_file("data/Miama.otf", "build/data/Miama.otf");
    
    // tell the compiler to use our own modules as an import path as well
    import_path: [..] string;
    array_add(*import_path, "modules");
    array_add(*import_path, ..options.import_path);
    options.import_path = import_path;

    // make workspace and set the options
    w := compiler_create_workspace(options.output_executable_name);
    set_build_options(options, w);
    if !w {
        print("Workspace creation failed.\n");
        return;
    }
    
    compiler_begin_intercept(w);  // tell compiler to give messages

    {
        add_build_file("guitar.jai", w);  // add source

        // compiler message loop
        failed := false;
        while true {
            message := compiler_wait_for_message();
            if message.workspace != w continue;
            if message.kind == .COMPLETE {
                m := cast(*Message_Complete) message;
                if m.error_code == .COMPILATION_FAILED then failed = true;
                break;
            }
        }
    }
    
    compiler_end_intercept(w);  // done compiling

    print("\n");

    // this file is purely to build, so don't make a exe for first.
    set_build_options_dc(.{do_output=false});
}

#run build();

#import "Basic";
#import "Compiler";
#import "File";            // make_file...
#import "File_Utilities";  // copy_file

