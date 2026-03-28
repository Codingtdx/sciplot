import type { SelectHTMLAttributes } from "react";

type MacSelectOption = {
  value: string;
  label: string;
};

type MacSelectProps = SelectHTMLAttributes<HTMLSelectElement> & {
  label: string;
  options: MacSelectOption[];
};

export function MacSelect({ label, options, ...props }: MacSelectProps) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      <select {...props}>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  );
}
