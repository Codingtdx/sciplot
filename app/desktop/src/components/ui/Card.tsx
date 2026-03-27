import React from 'react';
import './Card.css';

interface CardProps {
  children: React.ReactNode;
  variant?: 'default' | 'elevated';
  className?: string;
}

export const Card: React.FC<CardProps> = ({ 
  children, 
  variant = 'default', 
  className = '' 
}) => {
  const baseClass = 'sciplot-card';
  const classes = [
    baseClass,
    `${baseClass}--${variant}`,
    className
  ].filter(Boolean).join(' ');

  return (
    <div className={classes}>
      {children}
    </div>
  );
};
