"""Utility functions for generating protobuf code."""

_PROTO_EXTENSION = ".proto"

def well_known_proto_libs():
    return [
        "@com_google_protobuf//:any_proto",
        "@com_google_protobuf//:api_proto",
        "@com_google_protobuf//:compiler_plugin_proto",
        "@com_google_protobuf//:descriptor_proto",
        "@com_google_protobuf//:duration_proto",
        "@com_google_protobuf//:empty_proto",
        "@com_google_protobuf//:field_mask_proto",
        "@com_google_protobuf//:source_context_proto",
        "@com_google_protobuf//:struct_proto",
        "@com_google_protobuf//:timestamp_proto",
        "@com_google_protobuf//:type_proto",
        "@com_google_protobuf//:wrappers_proto",
    ]

def get_proto_root(workspace_root):
    """Gets the root protobuf directory.

    Args:
      workspace_root: context.label.workspace_root

    Returns:
      The directory relative to which generated include paths should be.
    """
    if workspace_root:
        return "/{}".format(workspace_root)
    else:
        return ""

def _strip_proto_extension(proto_filename):
    if not proto_filename.endswith(_PROTO_EXTENSION):
        fail('"{}" does not end with "{}"'.format(
            proto_filename,
            _PROTO_EXTENSION,
        ))
    return proto_filename[:-len(_PROTO_EXTENSION)]

def proto_path_to_generated_filename(proto_path, fmt_str):
    """Calculates the name of a generated file for a protobuf path.

    For example, "examples/protos/helloworld.proto" might map to
      "helloworld.pb.h".

    Args:
      proto_path: The path to the .proto file.
      fmt_str: A format string used to calculate the generated filename. For
        example, "{}.pb.h" might be used to calculate a C++ header filename.

    Returns:
      The generated filename.
    """
    return fmt_str.format(_strip_proto_extension(proto_path))

def _get_include_directory(include):
    directory = include.path
    prefix_len = 0
    if not include.is_source and directory.startswith(include.root.path):
        prefix_len = len(include.root.path) + 1

    if directory.startswith("external", prefix_len):
        external_separator = directory.find("/", prefix_len)
        repository_separator = directory.find("/", external_separator + 1)
        return directory[:repository_separator]
    else:
        return include.root.path if include.root.path else "."

def get_include_protoc_args(includes):
    """Returns protoc args that imports protos relative to their import root.

    Args:
      includes: A list of included proto files.

    Returns:
      A list of arguments to be passed to protoc. For example, ["--proto_path=."].
    """
    return [
        "--proto_path={}".format(_get_include_directory(include))
        for include in includes
    ]

def get_plugin_args(plugin, flags, dir_out, generate_mocks):
    """Returns arguments configuring protoc to use a plugin for a language.

    Args:
      plugin: An executable file to run as the protoc plugin.
      flags: The plugin flags to be passed to protoc.
      dir_out: The output directory for the plugin.
      generate_mocks: A bool indicating whether to generate mocks.

    Returns:
      A list of protoc arguments configuring the plugin.
    """
    augmented_flags = list(flags)
    if generate_mocks:
        augmented_flags.append("generate_mock_code=true")
    return [
        "--plugin=protoc-gen-PLUGIN=" + plugin.path,
        "--PLUGIN_out=" + ",".join(augmented_flags) + ":" + dir_out,
    ]

def _get_staged_proto_file(context, source_file):
    if source_file.dirname == context.label.package:
        return source_file
    else:
        copied_proto = context.actions.declare_file(source_file.basename)
        context.actions.run_shell(
            inputs = [source_file],
            outputs = [copied_proto],
            command = "cp {} {}".format(source_file.path, copied_proto.path),
            mnemonic = "CopySourceProto",
        )
        return copied_proto


def protos_from_context(context):
    """Copies proto files to the appropriate location.

    Args:
      context: The ctx object for the rule.

    Returns:
      A list of the protos.
    """
    protos = []
    for src in context.attr.deps:
        for file in src[ProtoInfo].direct_sources:
            protos.append(_get_staged_proto_file(context, file))
    return protos


def includes_from_deps(deps):
    """Get includes from rule dependencies."""
    return [
        file
        for src in deps
        for file in src[ProtoInfo].transitive_imports.to_list()
    ]

def get_proto_arguments(protos, genfiles_dir_path):
    """Get the protoc arguments specifying which protos to compile."""
    arguments = []
    for proto in protos:
        massaged_path = proto.path
        if massaged_path.startswith(genfiles_dir_path):
            massaged_path = proto.path[len(genfiles_dir_path) + 1:]
        arguments.append(massaged_path)
    return arguments

def declare_out_files(protos, context, generated_file_format):
    """Declares and returns the files to be generated."""
    return [
        context.actions.declare_file(
            proto_path_to_generated_filename(
                proto.basename,
                generated_file_format,
            ),
        )
        for proto in protos
    ]
