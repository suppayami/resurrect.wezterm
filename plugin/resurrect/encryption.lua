local wezterm = require("wezterm")

---@class encrypt_module
---@field encryption encryption_opts
local pub = {}

--- checks if the user is on windows
local is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"

---executes cmd and passes input to stdin
---@param cmd string command to be run
---@param input string input to stdin
---@return boolean
---@return string
local function execute_cmd_with_stdin(cmd, input)
	if is_windows and #input < 32000 then -- Check if input is larger than max cmd length on Windows
		cmd = string.format("%s | %s", wezterm.shell_join_args({ "Write-Output", "-NoEnumerate", input }), cmd)
		local process_args = { "pwsh.exe", "-NoProfile", "-Command", cmd }

		local success, stdout, stderr = wezterm.run_child_process(process_args)
		if success then
			return success, stdout
		else
			return success, stderr
		end
	elseif #input < 150000 and not is_windows then -- Check if input is larger than common max on MacOS and Linux
		cmd = string.format("%s | %s", wezterm.shell_join_args({ "echo", "-E", "-n", input }), cmd)
		local process_args = { os.getenv("SHELL"), "-c", cmd }

		local success, stdout, stderr = wezterm.run_child_process(process_args)
		if success then
			return success, stdout
		else
			return success, stderr
		end
	else
		-- redirect stderr to stdout to test if cmd will execute
		-- can't check on Windows because it doesn't support /dev/stdin
		if not is_windows then
			local stdout = io.popen(cmd .. " 2>&1", "r")
			if not stdout then
				return false, "Failed to execute: " .. cmd
			end
			local stderr = stdout:read("*all")
			stdout:close()
			if stderr ~= "" then
				wezterm.log_error(stderr)
				return false, stderr
			end
		end
		-- if no errors, execute cmd using stdin with input
		local stdin = io.popen(cmd, "w")
		if not stdin then
			return false, "Failed to execute: " .. cmd
		end
		stdin:write(input)
		stdin:flush()
		stdin:close()
		return true, '"' .. cmd .. '" <input> ran successfully.'
	end
end

---@param file_path string
---@param lines string
local function encrypt(file_path, lines)
	local cmd =
		string.format("%s -r %s -o %s", pub.encryption.method, pub.encryption.public_key, file_path:gsub(" ", "\\ "))

	if pub.encryption.method:find("gpg") then
		cmd = string.format(
			"%s --batch --yes --encrypt --recipient %s --output %s",
			pub.encryption.method,
			pub.encryption.public_key,
			file_path:gsub(" ", "\\ ")
		)
	end

	local success, output = execute_cmd_with_stdin(cmd, lines)
	if not success then
		error("Encryption failed:" .. output)
	end
end

---@param file_path string
---@return string
local function decrypt(file_path)
	local cmd = { pub.encryption.method, "-d", "-i", pub.encryption.private_key, file_path }

	if pub.encryption.method:find("gpg") then
		cmd = { pub.encryption.method, "--batch", "--yes", "--decrypt", file_path }
	end

	local success, stdout, stderr = wezterm.run_child_process(cmd)
	if not success then
		error("Decryption failed: " .. stderr)
	end

	return stdout
end

---@alias encryption_opts {enable: boolean, method: string, private_key: string?, public_key: string?, encrypt: fun(file_path: string, lines: string), decrypt: fun(file_path: string): string}
pub.encryption = {
	enable = false,
	method = "age",
	private_key = nil,
	public_key = nil,
	encrypt = encrypt,
	decrypt = decrypt,
}

--- Merges user-supplied options with default options
--- @param user_opts encryption_opts
function pub.set_encryption(user_opts)
	for k, v in pairs(user_opts) do
		if v ~= nil then
			pub.encryption[k] = v
		end
	end
end

return pub
