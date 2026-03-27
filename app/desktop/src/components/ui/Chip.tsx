import React from 'react';
import './Chip.css';

interface ChipProps {
  children: React.ReactNode;
  variant?: 'default' | 'selected' | 'inactive';
  onClick?: () => void;
  className?: string;
}

export const Chip: React.FC<ChipProps> = ({ 
  children, 
  variant = 'default', 
  onClick, 
  className = '' 
}) => {
  const baseClass = 'sciplot-chip';
  const classes = [
    baseClass,
    `${baseClass}--${variant}`,
    onClick ? `${baseClass}--clickable` : '',
    className
  ].filter(Boolean).join(' ');

  return (
    <div 
      className={classes}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? (e) => e.key === 'Enter' && onClick() : undefined}
    >
      {children}
    </div>
  );
};
