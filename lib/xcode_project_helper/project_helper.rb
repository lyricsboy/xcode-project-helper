require 'xcodeproj'
require 'thor'
require 'fileutils'

module XcodeProjectHelper
  
  class ProjectHelper < Thor
  
    desc "move_file project_file file_path", "Move a file between targets."
    option :from_target, :required => true
    option :to_target, :required => true
    option :to_group, :required => false
    def move_file(project_file, filename)
      raise Thor::Error.new("File '#{filename}' not found.") unless File.exists? filename
      absolute_filename = File.absolute_path(filename)
      
      puts "Using project '#{project_file}'"
      project = Xcodeproj::Project.open(project_file)
      
      puts "Attempting to find file matching path '#{absolute_filename}'"
      file = project.files.find { |f| f.real_path.to_s == absolute_filename }
      raise Thor::Error.new("File '#{filename}' not found in project.") unless file
      
      from_target_name = options[:from_target]
      from_target = project.native_targets.find { |t| t.name == from_target_name }
      raise Thor::Error.new("Native target '#{from_target_name}' not found.") unless from_target
      
      to_target_name = options[:to_target]
      to_target = project.native_targets.find { |t| t.name == to_target_name }
      raise Thor::Error.new("Native target '#{to_target_name}' not found.") unless to_target
      
      raise Thor::Error.new("From and to targets must be different.") if from_target == to_target
      
      to_group_name = options[:to_group] || to_target_name
      matching_groups = project.groups.find_all { |g| g.display_name == to_group_name }
      raise Thor::Error.new("Group name '#{to_group_name}' not found.") unless matching_groups.size > 0
      raise Thor::Error.new("Group name '#{to_group_name}' is ambiguous.") unless matching_groups.size == 1
      to_group = matching_groups.first
      
      # attempt to find the file in the resources and source build phases, 
      # and use that build phase type for the to_target
      build_phase_to_fileref_map = Hash.new
      [from_target.resources_build_phase, from_target.source_build_phase].each do |phase|
        file_ref = phase.files_references.find { |f| f.real_path.to_s == absolute_filename }
        build_phase_to_fileref_map[phase] = file_ref if file_ref
      end
      raise Thor::Error.new("File '#{filename}' not found in any of '#{from_target_name}' target's known build phases.") unless build_phase_to_fileref_map.size > 0
      puts "Found '#{filename}' in these build phases: " + build_phase_to_fileref_map.keys.map { |phase| phase.display_name }.join(', ')
      
      puts
      puts "Attempting to move file '#{filename}'."
      puts "  From target: '#{from_target_name}'"
      puts "  To target: '#{to_target_name}'"
      puts "  To group: '#{to_group.display_name}"
      
      # for each build phase:
      build_phase_to_fileref_map.each do |phase, fileref|
        # get the full path to the fileref
        old_path = fileref.real_path
        # remove the fileref from it
        phase.remove_file_reference(fileref)
        # then move the fileref from its existing parent to the new group
        fileref.move(to_group)
        # and move the file on disk
        FileUtils.move(old_path, to_group.real_path)
        # then add the new fileref to the same type of build phase for the new target
        if phase.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
          to_target.add_file_references([fileref])
        elsif phase.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
          to_target.add_resources([fileref])
        else
          raise Thor::Error.new("Unknown type of build phase: " + phase.class)
        end
      end
      
      # save the project file
      project.save
    end
  end
  
end