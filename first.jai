build :: () {
    // create build options and set the output exe name
    options := get_build_options();
    options.output_executable_name = "guitar";
    
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

    add_build_file("guitar.jai", w);  // add out source
    
    // compiler message loop (only check for failure
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

    compiler_end_intercept(w);  // done compiling

    print("\n");

    // this file is purely to build, so don't make a exe for first.
    set_build_options_dc(.{do_output=false});
}

#run build();

#import "Basic";
#import "Compiler";

